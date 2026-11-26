# Substage 5: Migration to Envoy Gateway API

This substage completes the networking progression by migrating from the legacy `Ingress` API to the modern Kubernetes **Gateway API** powered by **Envoy Gateway v1.5.0**. This architecture forms the canonical edge baseline that carries forward into Stages 3 and beyond.

---

## 1. Build

### 1.1 Decommission Traefik (Clean Handover)
Before activating Envoy Gateway, remove the transitional Traefik controller and its Ingress resources:

```bash
kubectl delete ingress --all -n apollo-airlines-apps --ignore-not-found
kubectl delete ingress --all -n apollo-airlines-ui --ignore-not-found
kubectl delete service traefik -n kube-system --ignore-not-found
kubectl delete daemonset traefik -n kube-system --ignore-not-found
kubectl delete ingressclass traefik --ignore-not-found
kubectl delete clusterrolebinding traefik --ignore-not-found
kubectl delete clusterrole traefik --ignore-not-found
kubectl delete serviceaccount traefik -n kube-system --ignore-not-found
```

### 1.2 Install Envoy Gateway Controller & CRDs
Install Envoy Gateway v1.5.0 using server-side apply (required because Gateway API CRDs exceed the 256KB client-side annotation limit):

```bash
kubectl apply --server-side -f stages/stage2/k8s/substages/05-envoy-gateway/00-envoy-gateway-install.yaml

# Wait for the Envoy Gateway controller to be ready
kubectl wait --namespace envoy-gateway-system \
  --for=condition=ready pod \
  --selector=control-plane=envoy-gateway \
  --timeout=120s
```

### 1.3 Deploy Gateway API Resources
Apply the GatewayClass, EnvoyProxy configuration, Gateway, ReferenceGrant, and HTTPRoutes:

```bash
# GatewayClass specifies the controller implementation
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/00a-gatewayclass.yaml

# EnvoyProxy instructs Envoy Gateway to provision a type: LoadBalancer service for MetalLB
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/00b-envoyproxy.yaml

# Ensure the local wildcard TLS Secret exists for the Gateway HTTPS listener
./stages/stage2/k8s/substages/03-traefik-ingress-tls/generate-certs.sh

# Gateway defines the listening port and allowed route namespaces
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/01-gateway.yaml

# ReferenceGrant allows cross-namespace service references
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml

# HTTPRoutes map hostnames to backend services
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/02-httproute-identity.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/03-httproute-flight.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/04-httproute-booking.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/05-httproute-search.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/06-httproute-notification.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/07-httproute-frontend.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/08-httproute-cross-ns-refgrant.yaml
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/09-httproute-https-redirect.yaml
```

---

## 2. Inspect

### CRD & Controller Literacy
Verify the Gateway API CustomResourceDefinitions (CRDs) registered on the cluster:

```bash
kubectl get crd | grep -E "gateway\.networking\.k8s\.io|envoyproxy\.io"
```

### Gateway Status & Programming
Inspect the Gateway object to confirm that the Envoy Gateway controller accepted and programmed the listeners:

```bash
kubectl get gateway apollo-gateway -n apollo-airlines-apps
```
Check conditions in detailed status:
```bash
kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.message}){"\n"}{end}'
```
Expected: `Accepted=True`, `Programmed=True`.

### Auto-Provisioned Envoy Proxy
Envoy Gateway dynamically creates an Envoy proxy Deployment and Service configured as `type: LoadBalancer`:

```bash
kubectl get svc -n envoy-gateway-system
```
MetalLB assigns an `EXTERNAL-IP` (e.g. `172.18.0.50`) to this Envoy service.

### Verify HTTPRoutes and End-to-End Traffic
List all active HTTPRoute rules:
```bash
kubectl get httproute -A
```

Query endpoints through Envoy Gateway using the allocated LoadBalancer IP:
```bash
EG_IP=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "Envoy Gateway IP: $EG_IP"

# Test identity endpoint
curl -s -H "Host: identity.apollo.local" "http://${EG_IP}/healthz"

# Test flight endpoint
curl -s -H "Host: flight.apollo.local" "http://${EG_IP}/healthz"

# Test frontend HTML
curl -sI -H "Host: frontend.apollo.local" "http://${EG_IP}/" | head -n 1

# Test cross-namespace ReferenceGrant route (apollo-airlines-apps HTTPRoute -> apollo-airlines-ui Service)
curl -sI -H "Host: cross-ns.apollo.local" "http://${EG_IP}/" | head -n 1

# Test HTTP-to-HTTPS RequestRedirect filter (returns 301 Location: https://redirect.apollo.local/)
curl -sI -H "Host: redirect.apollo.local" "http://${EG_IP}/" | grep -iE '^(HTTP/|location:)'
```

---

## 3. Break (Safe, Reversible Failure)

### Lab A: Invalid Backend Port (`ResolvedRefs=False`)

Cross-namespace routing requires explicit trust boundaries. In `frontend`'s HTTPRoute (`apollo-airlines-ui`), it references the Gateway in `apollo-airlines-apps`. To test what happens when a route targets a broken backend port, patch the `frontend` HTTPRoute to point to `9999`:

```bash
kubectl patch httproute frontend -n apollo-airlines-ui --type='json' -p='[{"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 9999}]'
```

#### Observe Failure Evidence
Inspect the HTTPRoute's status condition:

```bash
kubectl get httproute frontend -n apollo-airlines-ui -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}: {.message}){"\n"}{end}'
```
Notice `ResolvedRefs=False` or backend resolution warnings!

Send a request through Envoy:
```bash
curl -sI -H "Host: frontend.apollo.local" "http://${EG_IP}/"
```
Envoy returns `HTTP/1.1 500 Internal Server Error` (no healthy upstream endpoints).

### Lab B: Missing `ReferenceGrant` (`RefNotPermitted`)

`08-httproute-cross-ns-refgrant.yaml` creates `HTTPRoute/frontend-cross-ns` in `apollo-airlines-apps` pointing to `Service/frontend` in `apollo-airlines-ui`. Because the route references a Service in a *different* namespace, Gateway API blocks it unless a `ReferenceGrant` in the target namespace (`apollo-airlines-ui`) permits it. Delete `01a-referencegrant.yaml`:

```bash
kubectl delete -f stages/stage2/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml
```

#### Observe Failure Evidence
```bash
kubectl get httproute frontend-cross-ns -n apollo-airlines-apps -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}: {.message}){"\n"}{end}'
curl -sI -H "Host: cross-ns.apollo.local" "http://${EG_IP}/" | head -n 1
```
Notice `ResolvedRefs=False (RefNotPermitted: ...)` and `HTTP/1.1 500 Internal Server Error`, while `frontend.apollo.local` (same-namespace backend) still returns `200 OK`.

---

## 4. Recover

### Recover Lab A (`frontend` port)
Restore the valid backend port (`3000`):

```bash
kubectl patch httproute frontend -n apollo-airlines-ui --type='json' -p='[{"op": "replace", "path": "/spec/rules/0/backendRefs/0/port", "value": 3000}]'
```

### Verify Lab A Recovery
Check the HTTPRoute condition:

```bash
kubectl get httproute frontend -n apollo-airlines-ui -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status}{"\n"}{end}'
```
`ResolvedRefs=True` and `Accepted=True`.

Query the frontend endpoint again:
```bash
curl -sI -H "Host: frontend.apollo.local" "http://${EG_IP}/" | head -n 1
```
Output returns `HTTP/1.1 200 OK`.

### Recover Lab B (`ReferenceGrant`)
Re-apply `01a-referencegrant.yaml`:

```bash
kubectl apply -f stages/stage2/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml
kubectl get httproute frontend-cross-ns -n apollo-airlines-apps -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
curl -sI -H "Host: cross-ns.apollo.local" "http://${EG_IP}/" | head -n 1
```
`ResolvedRefs=True` returns and `cross-ns.apollo.local` serves `HTTP/1.1 200 OK`.

---

## 5. Explain

1. **Why does Gateway API replace Ingress?**
   - **Role-oriented design:** Separates concerns between Cluster Operators (GatewayClass), Infrastructure/Security Admins (Gateway, TLS, listeners), and Application Developers (HTTPRoute, GRPCRoute).
   - **Native cross-namespace routing:** Securely attaches routes across namespaces without vendor-specific annotations.
   - **Expressiveness:** Built-in support for header modifications, weighted routing, redirects, mirroring, and granular status reporting without custom annotations.
2. **What role does `EnvoyProxy` play?**
   - In Envoy Gateway, the `EnvoyProxy` CRD defines implementation-specific settings for the data plane (e.g. Service type `LoadBalancer`, replicas, resource limits, logging). It binds to the Gateway via `spec.infrastructure.parametersRef`.
3. **How does Envoy Gateway reconcile changes?**
   - The controller watches Gateway API resources and translates them into Envoy xDS protocol configurations, streaming dynamic routing rules directly to Envoy proxy instances without restarting pods.
4. **Why is `ReferenceGrant` required for cross-namespace `backendRefs`, and what does `RequestRedirect` do?**
   - `Gateway.spec.listeners[].allowedRoutes` controls which namespaces can *attach* routes to a Gateway, whereas `ReferenceGrant` (in the *target* Service's namespace) prevents a route in namespace A from secretly forwarding traffic to a Service in namespace B (`RefNotPermitted` when absent).
   - `RequestRedirect` filters respond directly at the Envoy edge (e.g. `301` `Location: https://...` from `sectionName: http`) without forwarding to any `backendRefs`.
