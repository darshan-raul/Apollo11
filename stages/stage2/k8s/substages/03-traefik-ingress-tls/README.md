# Substage 3: Traefik Ingress & Controlled Local TLS

This substage moves edge access from raw Layer 4 NodePorts to a Layer 7 Ingress controller (Traefik v3). It demonstrates host-based HTTP routing on a single ingress port and terminates local TLS encryption using a Kubernetes Secret.

---

## 1. Build

### 1.1 Generate Local TLS Secret
Generate a self-signed wildcard certificate for `*.apollo.local` and store it as a TLS Secret:

```bash
./stages/stage2/k8s/substages/03-traefik-ingress-tls/generate-certs.sh
```

### 1.2 Deploy Traefik Controller & Ingresses
Deploy Traefik RBAC, IngressClass, DaemonSet, NodePort Service, and Ingress rules:

```bash
kubectl apply -f stages/stage2/k8s/substages/03-traefik-ingress-tls/00-traefik-rbac-and-class.yaml
kubectl apply -f stages/stage2/k8s/substages/03-traefik-ingress-tls/01-traefik-daemonset.yaml
kubectl apply -f stages/stage2/k8s/substages/03-traefik-ingress-tls/01b-traefik-service.yaml
kubectl apply -f stages/stage2/k8s/substages/03-traefik-ingress-tls/02-ingress-frontend.yaml
kubectl apply -f stages/stage2/k8s/substages/03-traefik-ingress-tls/03-ingress-apps.yaml

# Wait for Traefik DaemonSet pod to become ready
kubectl rollout status daemonset/traefik -n kube-system --timeout=60s
```

---

## 2. Inspect

### Ingress & Route Inspection
Check the configured Ingress resources:

```bash
kubectl get ingress -A
```
Observe that all Ingress resources share the `traefik` IngressClass, specify distinct `hosts` (`*.apollo.local`), and configure TLS termination with `apollo-tls-secret`.

### L7 HTTP Host-Based Routing
Send HTTP requests through Traefik's web port (`30080`) using different `Host` headers:

```bash
# Routes to identity service
curl -s -H "Host: identity.apollo.local" http://localhost:30080/healthz

# Routes to flight service
curl -s -H "Host: flight.apollo.local" http://localhost:30080/healthz
```

### TLS Handshake & Certificate Verification
Query the HTTPS endpoint (`30443`) and inspect the presented TLS certificate:

```bash
curl -k -v --resolve identity.apollo.local:30443:127.0.0.1 https://identity.apollo.local:30443/healthz 2>&1 | grep -E "Server certificate|subject:"
```
Expected output shows the certificate subject:
```
*  subject: CN=*.apollo.local
```

---

## 3. Break (Safe, Reversible Failure)

Delete the TLS secret in both namespaces to observe how the ingress controller handles missing certificate secrets. Traefik pools every certificate it can read, and `apollo-airlines-ui` holds a copy of the same wildcard, so deleting only the `apollo-airlines-apps` copy leaves `*.apollo.local` still being served:

```bash
kubectl delete secret apollo-tls-secret -n apollo-airlines-apps
kubectl delete secret apollo-tls-secret -n apollo-airlines-ui
```

### Observe Failure Evidence
Query the HTTPS endpoint again:

```bash
curl -k -v --resolve identity.apollo.local:30443:127.0.0.1 https://identity.apollo.local:30443/healthz 2>&1 | grep "subject:"
```
Observe that Traefik no longer serves the `*.apollo.local` certificate. Instead, it falls back to its default internal certificate (`TRAEFIK DEFAULT CERT`), causing clients expecting your trusted wildcard certificate to reject the connection!

---

## 4. Recover

Re-run the certificate provisioning script:

```bash
./stages/stage2/k8s/substages/03-traefik-ingress-tls/generate-certs.sh
```

### Verify Recovery
Query the endpoint again and verify that the custom certificate is restored:

```bash
curl -k -v --resolve identity.apollo.local:30443:127.0.0.1 https://identity.apollo.local:30443/healthz 2>&1 | grep "subject:"
```
Output confirms: `* subject: CN=*.apollo.local`.

---

## 5. Explain

1. **How does Layer 7 Host routing differ from Layer 4 NodePort?**
   - NodePort allocates a separate TCP port per service on every node.
   - An Ingress controller listens on standard HTTP/HTTPS ports (80/443), parses the incoming HTTP `Host` header and URL path, and proxies the request to the matching ClusterIP service.
2. **What is TLS termination at the edge?**
   - The ingress controller decrypts incoming TLS traffic using the certificate and private key stored in the Kubernetes Secret.
   - Communication between the ingress controller and backend application pods flows in cleartext (or via internal mTLS), offloading CPU-intensive crypto operations from application pods.
3. **Why did Traefik serve `TRAEFIK DEFAULT CERT` when the secret was deleted?**
   - Rather than dropping the TCP connection, Traefik uses a built-in self-signed fallback certificate so the TLS handshake can still complete while logging a warning about the missing secret.
