## Ssh key

ssh-keygen -t ed25519 -C "<email>"
cat gcloud.pub 
>> put this public key in github

vim .ssh/config 
> put entries here

```
Host github.com
	IdentityFile ~/.ssh/gcloud

```

---

## GPG key

gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
gpg --armor --export 3B4EC0F8B228C21D
git config --global --unset gpg.format
gpg --list-secret-keys --keyid-format=long
git config --global user.signingkey 3B4EC0F8B228C21D
git config --global commit.gpgsign true
[ -f ~/.bashrc ] && echo -e '\nexport GPG_TTY=$(tty)' >> ~/.bashrc

---

## Git config setup

git config --global user.email "<email>"
git config --global user.name "<Full Name>"

---------


## Gcloud instance setup


### 1 controller

```
for i in 0; do
  gcloud compute instances create controller-${i} \
    --async \
    --zone=us-central1-a \
    --machine-type=t2a-standard-1 \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-2204-lts-arm64 \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-standard \
    --tags kubernetes-the-kubespray-way,controller
done
```

### 2 workers

```
for i in 0 1; do
  gcloud compute instances create worker-${i} \
    --async \
    --zone=us-central1-a \
    --machine-type=t2a-standard-1 \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-2204-lts-arm64 \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-standard \
    --tags kubernetes-the-kubespray-way,worker
done
```

Put this in ssh config

```


```

### Delete instances [after the exercise]

```
gcloud -q compute instances delete \
  controller-0 controller-1 controller-2 \
  worker-0 worker-1 worker-2 \
  --zone $(gcloud config get-value compute/zone)
```

### K8s the hard way

chapter2 - on jump server

```
    sudo -i

    apt-get -y install wget curl vim openssl git

    git clone --depth 1 \
    https://github.com/kelseyhightower/kubernetes-the-hard-way.git

    cd kubernetes-the-hard-way

    mkdir downloads
    cat downloads.txt

    wget -q --show-progress \
    --https-only \
    --timestamping \
    -P downloads \
    -i downloads.txt

    ls -loh downloads

    {
    chmod +x downloads/kubectl
    cp downloads/kubectl /usr/local/bin/
    }

    kubectl version --client
```

chapter 3 - host and root access setup

```

    create machines.txt

    ```
    XXX.XXX.XXX.XXX server.kubernetes.local server  
    XXX.XXX.XXX.XXX node-0.kubernetes.local node-0 10.200.0.0/24
    XXX.XXX.XXX.XXX node-1.kubernetes.local node-1 10.200.1.0/24
    ```

    tmux on each machine: setw synchronize-panes on

        sudo -i

        sed -i \
        's/^#PermitRootLogin.*/PermitRootLogin yes/' \
        /etc/ssh/sshd_config

        systemctl restart sshd


    while read IP FQDN HOST SUBNET; do 
    ssh -n root@${HOST} uname -o -m
    done < machines.txt


    while read IP FQDN HOST SUBNET; do 
        CMD="sed -i 's/^127.0.0.1.*/127.0.0.1\t${FQDN} ${HOST}/' /etc/hosts"
        ssh -n root@${HOST} "$CMD"
        ssh -n root@${HOST} hostnamectl hostname ${HOST}
    done < machines.txt

    while read IP FQDN HOST SUBNET; do
    ssh -n root@${HOST} hostname --fqdn
    done < machines.txt


    echo "" > hosts
    echo "# Kubernetes The Hard Way" >> hosts

    while read IP FQDN HOST SUBNET; do 
    ENTRY="${IP} ${FQDN} ${HOST}"
    echo $ENTRY >> hosts
    done < machines.txt


    cat hosts


    cat hosts >> /etc/hosts
    cat /etc/hosts

    for host in server node-0 node-1
    do ssh root@${host} uname -o -m -n
    done

    while read IP FQDN HOST SUBNET; do
    scp hosts root@${HOST}:~/
    ssh -n \
        root@${HOST} "cat hosts >> /etc/hosts"
    done < machines.txt

```

chapter 4 - cert setup

```

    cat ca.conf

    {
    openssl genrsa -out ca.key 4096
    openssl req -x509 -new -sha512 -noenc \
        -key ca.key -days 3653 \
        -config ca.conf \
        -out ca.crt
    }

    certs=(
    "admin" "node-0" "node-1"
    "kube-proxy" "kube-scheduler"
    "kube-controller-manager"
    "kube-api-server"
    "service-accounts"
    )

    for i in ${certs[*]}; do
    openssl genrsa -out "${i}.key" 4096

    openssl req -new -key "${i}.key" -sha256 \
        -config "ca.conf" -section ${i} \
        -out "${i}.csr"
    
    openssl x509 -req -days 3653 -in "${i}.csr" \
        -copy_extensions copyall \
        -sha256 -CA "ca.crt" \
        -CAkey "ca.key" \
        -CAcreateserial \
        -out "${i}.crt"
    done


    for host in node-0 node-1; do
    ssh root@$host mkdir /var/lib/kubelet/
    
    scp ca.crt root@$host:/var/lib/kubelet/
        
    scp $host.crt \
        root@$host:/var/lib/kubelet/kubelet.crt
        
    scp $host.key \
        root@$host:/var/lib/kubelet/kubelet.key
    done


    scp \
    ca.key ca.crt \
    kube-api-server.key kube-api-server.crt \
    service-accounts.key service-accounts.crt \
    root@server:~/

```

chapter 5 - configuration file setup

```

for host in node-0 node-1; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-credentials system:node:${host} \
    --client-certificate=${host}.crt \
    --client-key=${host}.key \
    --embed-certs=true \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${host} \
    --kubeconfig=${host}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${host}.kubeconfig
done


{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-proxy.kubeconfig
}

{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-controller-manager.kubeconfig
}

{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-scheduler.kubeconfig
}

{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default \
    --kubeconfig=admin.kubeconfig
}


for host in node-0 node-1; do
  ssh root@$host "mkdir /var/lib/{kube-proxy,kubelet}"
  
  scp kube-proxy.kubeconfig \
    root@$host:/var/lib/kube-proxy/kubeconfig \
  
  scp ${host}.kubeconfig \
    root@$host:/var/lib/kubelet/kubeconfig
done

scp admin.kubeconfig \
  kube-controller-manager.kubeconfig \
  kube-scheduler.kubeconfig \
  root@server:~/

```

chapter 6 - data encryption keys

```
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)


create extra file [missing from git repo, sources from a pull request]

"""
vim configs/encryption-config.yaml

kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}

"""


envsubst < configs/encryption-config.yaml \
  > encryption-config.yaml

scp encryption-config.yaml root@server:~/

```

chapter 7 - setting up etcd cluster

```


scp \
  downloads/etcd-v3.4.27-linux-arm64.tar.gz \
  units/etcd.service \
  root@server:~/

ssh root@server

{
  tar -xvf etcd-v3.4.27-linux-arm64.tar.gz
  mv etcd-v3.4.27-linux-arm64/etcd* /usr/local/bin/
}

{
  mkdir -p /etc/etcd /var/lib/etcd
  chmod 700 /var/lib/etcd
  cp ca.crt kube-api-server.key kube-api-server.crt \
    /etc/etcd/
}

mv etcd.service /etc/systemd/system/

{
  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd
}

etcdctl member list

```

chapter 8 - Bootstrapping the Kubernetes Control Plane

```

scp \
  downloads/kube-apiserver \
  downloads/kube-controller-manager \
  downloads/kube-scheduler \
  downloads/kubectl \
  units/kube-apiserver.service \
  units/kube-controller-manager.service \
  units/kube-scheduler.service \
  configs/kube-scheduler.yaml \
  configs/kube-apiserver-to-kubelet.yaml \
  root@server:~/


ssh root@server

mkdir -p /etc/kubernetes/config

{
  chmod +x kube-apiserver \
    kube-controller-manager \
    kube-scheduler kubectl
    
  mv kube-apiserver \
    kube-controller-manager \
    kube-scheduler kubectl \
    /usr/local/bin/
}

{
  mkdir -p /var/lib/kubernetes/

  mv ca.crt ca.key \
    kube-api-server.key kube-api-server.crt \
    service-accounts.key service-accounts.crt \
    encryption-config.yaml \
    /var/lib/kubernetes/
}

mv kube-apiserver.service \
  /etc/systemd/system/kube-apiserver.service

mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
mv kube-controller-manager.service /etc/systemd/system/


mv kube-scheduler.kubeconfig /var/lib/kubernetes/
mv kube-scheduler.yaml /etc/kubernetes/config/
mv kube-scheduler.service /etc/systemd/system/


{
  systemctl daemon-reload
  
  systemctl enable kube-apiserver \
    kube-controller-manager kube-scheduler
    
  systemctl start kube-apiserver \
    kube-controller-manager kube-scheduler
}

## after 10 seconds
kubectl cluster-info \
  --kubeconfig admin.kubeconfig


-- rbac

kubectl apply -f kube-apiserver-to-kubelet.yaml \
  --kubeconfig admin.kubeconfig

-- confirm connectivity

curl -k --cacert ca.crt https://server.kubernetes.local:6443/version

```

chapter 9Configuring kubectl for Remote Access
 - bootstraping worker nodes

```


for host in node-0 node-1; do
  SUBNET=$(grep $host machines.txt | cut -d " " -f 4)
  sed "s|SUBNET|$SUBNET|g" \
    configs/10-bridge.conf > 10-bridge.conf 
    
  sed "s|SUBNET|$SUBNET|g" \
    configs/kubelet-config.yaml > kubelet-config.yaml
    
  scp 10-bridge.conf kubelet-config.yaml \
  root@$host:~/
done


for host in node-0 node-1; do
  scp \
    downloads/runc.arm64 \
    downloads/crictl-v1.28.0-linux-arm.tar.gz \
    downloads/cni-plugins-linux-arm64-v1.3.0.tgz \
    downloads/containerd-1.7.8-linux-arm64.tar.gz \
    downloads/kubectl \
    downloads/kubelet \
    downloads/kube-proxy \
    configs/99-loopback.conf \
    configs/containerd-config.toml \
    configs/kube-proxy-config.yaml \
    units/containerd.service \
    units/kubelet.service \
    units/kube-proxy.service \
    root@$host:~/
done


-- run below commands on each worker node

swapon --show

-- > if output not blank: swapoff -a

mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

{
  mkdir -p containerd
  tar -xvf crictl-v1.28.0-linux-arm.tar.gz
  tar -xvf containerd-1.7.8-linux-arm64.tar.gz -C containerd
  tar -xvf cni-plugins-linux-arm64-v1.3.0.tgz -C /opt/cni/bin/
  mv runc.arm64 runc
  chmod +x crictl kubectl kube-proxy kubelet runc 
  mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
  mv containerd/bin/* /bin/
}


mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

{
  mkdir -p /etc/containerd/
  mv containerd-config.toml /etc/containerd/config.toml
  mv containerd.service /etc/systemd/system/
}

{
  mv kubelet-config.yaml /var/lib/kubelet/
  mv kubelet.service /etc/systemd/system/
}

{
  mv kube-proxy-config.yaml /var/lib/kube-proxy/
  mv kube-proxy.service /etc/systemd/system/
}

{
  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl start containerd kubelet kube-proxy
}
```

chapter 10 - Configuring kubectl for Remote Access

```


curl -k --cacert ca.crt \
  https://server.kubernetes.local:6443/version

{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key

  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

  kubectl config use-context kubernetes-the-hard-way
}


kubectl version
kubectl get nodes
```

chapter 11 - Provisioning Pod Network Routes

```

{
  SERVER_IP=$(grep server machines.txt | cut -d " " -f 1)
  NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1)
  NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 4)
  NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1)
  NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 4)

  echo "SERVER_IP = ${SERVER_IP}"
  echo "NODE_0_IP = ${NODE_0_IP}"
  echo "NODE_0_SUBNET = ${NODE_0_SUBNET}"
  echo "NODE_1_IP = ${NODE_1_IP}"
  echo "NODE_1_SUBNET = ${NODE_1_SUBNET}"
}

>>> below commands not working, i had to put them manually

ssh root@server <<EOF
  ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
  ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF

ssh root@node-0 <<EOF
  ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF

ssh root@node-1 <<EOF
  ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
EOF


```
