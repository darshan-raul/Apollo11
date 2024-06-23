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