# Substage 4: MetalLB & The LoadBalancer Service Model

In cloud environments (AWS, GCP, Azure), creating a `Service type: LoadBalancer` invokes cloud controller APIs to provision an external load balancer (NLB, ALB, etc.). In local clusters (like kind) or bare-metal environments, there is no default cloud controller. Without an on-prem controller, a LoadBalancer service remains permanently in `<pending>` state.

MetalLB monitors Services of type `LoadBalancer` and provides a network load-balancer implementation using standard Layer 2 (ARP/NDP) or BGP.

---

## 1. Build

### 1.1 Install MetalLB
Deploy the MetalLB controller and speaker DaemonSet:

```bash
kubectl apply -f stages/stage2/k8s/substages/04-metallb/00-metallb-native.yaml

# Wait for the controller and speaker to become ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=controller \
  --timeout=90s
```

### 1.2 Configure IP Address Pool & L2 Advertisement
Configure an IP pool on the Docker network (`172.18.0.50`–`172.18.0.100`) and advertise it via ARP:

```bash
kubectl apply -f stages/stage2/k8s/substages/04-metallb/01-ip-pool.yaml
```

### 1.3 Upgrade Traefik to `type: LoadBalancer`
Switch the Traefik Service from `type: NodePort` to `type: LoadBalancer`:

```bash
kubectl apply -f stages/stage2/k8s/substages/04-metallb/traefik-loadbalancer-svc.yaml
```

---

## 2. Inspect

### External-IP Allocation
Inspect the Traefik Service:

```bash
kubectl get svc traefik -n kube-system
```
Notice that `EXTERNAL-IP` is no longer `<pending>` — it has been assigned an IP such as `172.18.0.50`.

Save the assigned IP to an environment variable:
```bash
LB_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LoadBalancer IP: $LB_IP"
```

### Direct Access on Standard Ports (80 / 443)
Access the services on standard ports (no NodePort port numbers required!):

```bash
# HTTP via host routing on port 80:
curl -s -H "Host: identity.apollo.local" "http://${LB_IP}/healthz"

# HTTPS with TLS verification on port 443:
curl -k -s --resolve "identity.apollo.local:443:${LB_IP}" "https://identity.apollo.local/healthz"
```

---

## 3. Break (Safe, Reversible Failure)

To demonstrate how the LoadBalancer controller depends on an available IP address pool, delete the `IPAddressPool`:

```bash
kubectl delete ipaddresspool apollo-pool -n metallb-system
```

Now delete and recreate the Traefik service:

```bash
kubectl delete svc traefik -n kube-system
kubectl apply -f stages/stage2/k8s/substages/04-metallb/traefik-loadbalancer-svc.yaml
```

### Observe Failure Evidence
Check the service status:

```bash
kubectl get svc traefik -n kube-system
```
`EXTERNAL-IP` is stuck indefinitely in `<pending>`! MetalLB has no address pool from which to lease an IP.

---

## 4. Recover

Re-apply the IP pool manifest:

```bash
kubectl apply -f stages/stage2/k8s/substages/04-metallb/01-ip-pool.yaml
```

### Verify Recovery
Inspect the service again:

```bash
kubectl get svc traefik -n kube-system
```
Within seconds, MetalLB allocates an IP from the restored pool.

Verify traffic reachability:
```bash
LB_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s -H "Host: identity.apollo.local" "http://${LB_IP}/healthz"
```
Output returns HTTP 200 `{"status":"ok"}`.

---

## 5. Explain

1. **How does MetalLB Layer 2 mode work?**
   - When a service gets `type: LoadBalancer`, MetalLB selects an IP from the configured `IPAddressPool`.
   - The MetalLB speaker pod running on the cluster nodes sends gratuitous ARP announcements to the local network binding the service IP to the node's MAC address.
2. **Why didn't `type: LoadBalancer` work out of the box in kind?**
   - Kubernetes defines the `LoadBalancer` Service abstraction, but delegates the actual IP allocation and provisioning to external infrastructure controllers (cloud providers or MetalLB).
3. **What is the difference between Ingress and LoadBalancer?**
   - `LoadBalancer` is a Layer 4 (TCP/UDP) Kubernetes primitive that assigns a dedicated IP.
   - `Ingress` is a Layer 7 (HTTP/HTTPS) specification that defines routing rules based on hostnames and paths.
   - In production, they are typically combined: one LoadBalancer IP routes traffic to the Ingress controller, which distributes requests across many internal services.
