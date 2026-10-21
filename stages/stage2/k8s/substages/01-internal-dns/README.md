# Substage 1: Internal Discovery & Cross-Namespace DNS

This substage establishes internal cluster communication: Services with `type: ClusterIP`, automatic endpoint management via `Endpoints` and `EndpointSlices`, and cross-namespace DNS resolution via CoreDNS.

---

## 1. Build

All 10 Apollo Airlines workloads are deployed with `type: ClusterIP`. The core application and databases reside in `apollo-airlines-apps`, while the frontend web tier resides in `apollo-airlines-ui`.

Apply the test client pod in the UI namespace:
```bash
kubectl apply -f stages/stage2/k8s/substages/01-internal-dns/curl-client.yaml
kubectl wait --for=condition=Ready pod/curl-client -n apollo-airlines-ui --timeout=60s
```

---

## 2. Inspect

### Service & Endpoints Discovery
Each Service with a `selector` causes the Kubernetes control plane to automatically generate corresponding `Endpoints` and `EndpointSlice` resources that track ready Pod IPs:

```bash
# View services and their virtual ClusterIP addresses
kubectl get svc -n apollo-airlines-apps

# View the auto-populated pod endpoints behind the services
kubectl get endpoints -n apollo-airlines-apps

# Inspect modern EndpointSlices (scalable endpoint tracking)
kubectl get endpointslices -n apollo-airlines-apps
```

### Cross-Namespace DNS Resolution
Test how CoreDNS resolves short names vs Fully Qualified Domain Names (FQDNs) from within `apollo-airlines-ui`:

```bash
# 1. Cross-namespace short-name fails (searches apollo-airlines-ui.svc.cluster.local):
kubectl exec -n apollo-airlines-ui curl-client -- nslookup identity

# 2. Cross-namespace FQDN succeeds:
kubectl exec -n apollo-airlines-ui curl-client -- nslookup identity.apollo-airlines-apps.svc.cluster.local

# 3. Query the application over internal ClusterIP via FQDN:
kubectl exec -n apollo-airlines-ui curl-client -- curl -s http://identity.apollo-airlines-apps.svc.cluster.local:8080/healthz
# Expected output: {"status":"ok"}
```

---

## 3. Break (Safe, Reversible Failure)

Break the selector on the `identity` service so that it no longer matches any running identity pods:

```bash
kubectl patch svc identity -n apollo-airlines-apps -p '{"spec":{"selector":{"app":"identity-broken"}}}'
```

### Observe Failure Evidence
Immediately check the endpoints for `identity`:
```bash
kubectl get endpoints identity -n apollo-airlines-apps
```
Notice `ENDPOINTS` is `<none>`!

Now attempt to reach the service from `curl-client`:
```bash
kubectl exec -n apollo-airlines-ui curl-client -- curl -s --connect-timeout 3 http://identity.apollo-airlines-apps.svc.cluster.local:8080/healthz
```
The connection fails with a timeout or connection refused, even though the `identity` Pod is still healthy and running!

---

## 4. Recover

Restore the valid label selector to reconnect the Service to the Pods:

```bash
kubectl patch svc identity -n apollo-airlines-apps -p '{"spec":{"selector":{"app":"identity"}}}'
```

### Verify Recovery
Check that endpoints are instantly repopulated:
```bash
kubectl get endpoints identity -n apollo-airlines-apps
```
Re-run the HTTP query:
```bash
kubectl exec -n apollo-airlines-ui curl-client -- curl -s http://identity.apollo-airlines-apps.svc.cluster.local:8080/healthz
```
Output returns HTTP 200 `{"status":"ok"}`.

---

## 5. Explain

1. **How does CoreDNS resolve `<service>.<namespace>.svc.cluster.local`?**
   - Pods receive a search domain list in `/etc/resolv.conf` (e.g. `apollo-airlines-ui.svc.cluster.local`, `svc.cluster.local`, `cluster.local`).
   - A short name like `identity` only resolves if the target service is in the *same* namespace. Cross-namespace calls require at least `<service>.<namespace>`.
2. **What role do `Endpoints` and `EndpointSlices` play?**
   - Services do not route directly to Pods. The endpoint controller monitors Pods matching the Service's `selector` and updates `Endpoints` and `EndpointSlices`.
   - `kube-proxy` (or CNI) watches EndpointSlices and programs kernel packet routing rules (iptables or IPVS).
3. **Why can't an external browser reach a `ClusterIP`?**
   - ClusterIP addresses are virtual IPs allocated from an internal CIDR (e.g. `10.96.0.0/12`) that only exist within cluster nodes and pods. They are not routable outside the cluster network.
