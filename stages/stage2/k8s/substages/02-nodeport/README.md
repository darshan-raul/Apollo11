# Substage 2: NodePort External Access

This substage introduces `Service type: NodePort` as the first direct mechanism to access cluster workloads from the host machine or outside network.

---

## 1. Build

Transition public-facing services from internal `ClusterIP` to `NodePort`:

```bash
kubectl apply -f stages/stage2/k8s/substages/02-nodeport/nodeport-services.yaml
```

Allocated NodePorts:
- **Frontend:** `30080` (`apollo-airlines-ui`)
- **Flight:** `30081` (`apollo-airlines-apps`)
- **Booking:** `30082` (`apollo-airlines-apps`)
- **Identity:** `30083` (`apollo-airlines-apps`)
- **Search:** `30084` (`apollo-airlines-apps`)

---

## 2. Inspect

### Service Inspection
List services and verify that their types show `NodePort` with their allocated high ports:

```bash
kubectl get svc -n apollo-airlines-apps
kubectl get svc -n apollo-airlines-ui
```

### External Reachability from Host
Access the services directly using `localhost` and the allocated NodePorts:

```bash
# Query identity service health
curl -s http://localhost:30083/healthz
# Expected: {"status":"ok"}

# Query flight service health
curl -s http://localhost:30081/healthz
# Expected: {"service":"flight","status":"healthy"}

# Query frontend HTML
curl -sI http://localhost:30080 | head -n 1
# Expected: HTTP/1.1 200 OK
```

---

## 3. Break (Safe, Reversible Failure)

A common misconfiguration is a mismatch between the Service's `targetPort` and the container's listening port.

Patch the `identity` Service so its `targetPort` points to an unopened port (`9999`):

```bash
kubectl patch svc identity -n apollo-airlines-apps --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 9999}]'
```

### Observe Failure Evidence
Attempt to curl the NodePort from the host:

```bash
curl -s --connect-timeout 2 http://localhost:30083/healthz
```
The request fails with `Connection refused` or empty reply. The node accepted the packet on port 30083, but `kube-proxy` forwarded it to container port 9999, where nothing is listening!

---

## 4. Recover

Restore the `targetPort` back to `8080`:

```bash
kubectl patch svc identity -n apollo-airlines-apps --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'
```

### Verify Recovery
Query the endpoint again:

```bash
curl -s http://localhost:30083/healthz
```
Output returns HTTP 200 `{"status":"ok"}`.

---

## 5. Explain

1. **What is the difference between `port`, `targetPort`, and `nodePort`?**
   - `port`: The port exposed internally on the cluster-internal ClusterIP.
   - `targetPort`: The port on the Pod/container that processes receive incoming traffic on.
   - `nodePort`: The port exposed on every cluster node's external network interface (in the range 30000–32767).
2. **How does packet flow work with NodePort?**
   - Traffic hits `<NodeIP>:<NodePort>`.
   - `kube-proxy` packet filter rules (iptables or IPVS) intercept the packet on that node.
   - Traffic is NATed (DNAT) to one of the Pod IPs listed in the service's `Endpoints`, potentially forwarding across nodes.
3. **Why is NodePort not recommended as a long-term production edge solution?**
   - High non-standard port numbers (30000–32767) are impractical for end users and firewalls.
   - No Layer 7 routing (e.g. cannot route by hostname or URL path to multiple services on standard ports 80/443).
   - Port conflicts occur if two services request the same NodePort.
