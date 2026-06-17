---
title: "Stage 2 / Set 4: Traefik Ingress + MetalLB"
description: "Traefik v3 Ingress with type=LoadBalancer Service and a MetalLB L2 IPAddressPool (172.18.0.50-100). No NodePort gymnastics, no /etc/hosts collisions with kind's own IPs."
---

# Stage 2 / Set 4 — Traefik Ingress + MetalLB

Set 4 is the same Traefik v3 IngressController from Set 2/3, but with
one structural change: the Traefik **Service** is `type: LoadBalancer`
instead of `type: NodePort`. A real IP comes from **MetalLB** running
in L2 mode, so the access layer is no longer pinned to a `localhost`
port-forward or a kind `extraPortMappings` hack.

| | |
|---|---|
| **New concept** | `type: LoadBalancer` Service + MetalLB L2 IPAM |
| **Access pattern** | `curl -H 'Host: identity.apollo.local' http://172.18.0.50/...` (IP from MetalLB) |
| **Controller** | Traefik v3.1 (DaemonSet on control-plane) |
| **DNS** | `/etc/hosts` (5 entries → the IP MetalLB gave Traefik, printed by apply.sh) |
| **Result** | **26/26 verify checks pass** |

The **actual** new work vs Set 2/3 is **one file added + one file
modified**:

1. **`metallb/00-metallb-native.yaml`** (~1900 lines) — vendored
   MetalLB v0.14.5 native speaker install. Includes the
   controller, speaker, webhook, and CRDs.
2. **`metallb/01-ip-pool.yaml`** — two custom resources:
   an `IPAddressPool` (the IP range MetalLB is allowed to assign)
   + an `L2Advertisement` (how it announces those IPs — ARP/NDP
   on the local network).
3. **`ingress/01b-traefik-service.yaml`** (modified) — Traefik
   Service changed from `type: NodePort` to `type: LoadBalancer`.
   The `nodePort: 30443` line is gone.

Everything else (the 6 apps, 4 StatefulSets, 3 init jobs, the Traefik
DaemonSet, the 5 Ingresses) is identical to Set 2/3.

---

## Architecture

```
                          +-----------------------+
       Browser            |  kind docker network   |
         |                |                        |
         |                |  172.18.0.1  gateway   |  <- kind node IPs (DO NOT pool these)
         |                |  172.18.0.2  control   |
         |                |  172.18.0.3  worker    |
         |                |                        |
         |  HTTP          |  172.18.0.50  traefik  |  <- MetalLB-assigned (in the pool)
         v                |  ...                   |
   +------------+         |  172.18.0.100          |  <- end of pool
   |  Traefik   |  <----> |                        |
   |  Svc: LB   |  ARP    +-----------------------+
   +------------+
         |
         |  Routes by Host header
         |
   +---------+    +----------+    +---------+
   |identity |    | frontend |    | flight  |  ... (5 ClusterIP Services)
   +---------+    +----------+    +---------+

   /etc/hosts resolves *.apollo.local -> 172.18.0.50 (the MetalLB IP)
```

The Traefik pod is still on the control-plane node; the only thing
that changed is **how the network reaches it**. With NodePort, the
control-plane's host port 30443 is mapped; with LoadBalancer + MetalLB,
the kind network has a real ARP entry for 172.18.0.50 pointing at the
control-plane node's MAC.

---

## What's new vs Set 2/3 (file map)

```
k8s/
├── config/                          # (unchanged from Set 2/3)
│   ├── 00-namespaces.yaml
│   ├── configmap.yaml
│   └── secrets.yaml
├── serviceaccounts/                 # (unchanged)
├── networkpolicies/                 # reference only — kindnet doesn't enforce
├── apps/                            # (unchanged — 6 apps + 4 infra)
├── jobs/                            # (unchanged — 3 init jobs)
├── metallb/                         # ← NEW
│   ├── 00-metallb-native.yaml       # vendored install (~1900 lines)
│   └── 01-ip-pool.yaml              # IPAddressPool + L2Advertisement
└── ingress/                         # ← modified (01b is new type)
    ├── 00-traefik-rbac-and-class.yaml
    ├── 01-traefik-daemonset.yaml
    ├── 01b-traefik-service.yaml     # CHANGED: type: LoadBalancer
    ├── 02-ingress-frontend.yaml
    ├── 03-ingress-identity.yaml
    ├── 04-ingress-flight.yaml
    ├── 05-ingress-booking.yaml
    └── 06-ingress-search.yaml
```

---

## MetalLB — what it is and what it does

MetalLB is a **load-balancer implementation for bare-metal k8s
clusters** (which is exactly what kind is). When you set a Service
to `type: LoadBalancer` and there's no cloud provider in the cluster
(AWS ELB, GCP LB, Azure SLB), the Service stays in `<pending>`
indefinitely — the `status.loadBalancer.ingress` field never gets
populated. MetalLB fills that gap by watching Service objects of
`type: LoadBalancer` and assigning them IPs from a configured pool.

**Two ways MetalLB can announce the IPs:**

- **L2 mode** (used here): MetalLB responds to ARP requests for the
  pool IPs on the local network. From the kind docker bridge's
  perspective, 172.18.0.50 is now bound to a MAC address — the MAC
  of the kind node that runs the Service's pod. Standard, works
  anywhere, no router config required. Trade-off: only one node at a
  time handles traffic for the IP (though for a single-pod Traefik
  DaemonSet, that's fine).
- **BGP mode** (not used here): MetalLB peers with a BGP router and
  announces the pool IPs. Production-grade, but needs a real router
  in the network path. Useful for multi-node on-prem clusters.

**The two CRDs MetalLB defines:**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool        # the IP range
metadata:
  name: apollo-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.0.50-172.18.0.100
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement       # how to announce them
metadata:
  name: apollo-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - apollo-pool
```

The `L2Advertisement` is what binds a `type: LoadBalancer` Service
to a pool. Without it, the IPs in the pool exist but nothing tells
the network they should be routed to.

**Why the pool range matters:**

```
172.18.0.0/16   kind docker network (default)
├─ .1          kind host's docker bridge gateway
├─ .2          kind control-plane node
├─ .3, .4      kind worker nodes (default 1-worker config)
├─ .50 - .100  OUR POOL — MetalLB assigns these
└─ .255        kind broadcast address
```

The pool **must not overlap** with the kind node IPs. If you put
`172.18.0.2-172.18.0.100` in the pool, MetalLB will happily hand out
172.18.0.2 — and now ARP for that IP returns the speaker pod's MAC
instead of the control-plane node's MAC. Network traffic to the
control-plane (kubectl, kubelet, etc.) starts going to the wrong
machine. Subtle and painful to debug.

**Why `kubectl apply --server-side --force-conflicts`:**

```bash
kubectl apply --server-side --force-conflicts \
  -f k8s/metallb/00-metallb-native.yaml
```

- **`--server-side`**: the manifest is large (the namespace + 5
  CRDs + 4 deployments + 4 ClusterRoles + a few ConfigMaps + 2 webhooks
  totalling ~1900 lines). Server-side apply raises the
  `last-applied-config` annotation limit from 256KB to whatever the
  API server allows.
- **`--force-conflicts`**: MetalLB's `ValidatingWebhookConfiguration`
  has a self-signed CA that the controller rotates. The first apply
  will conflict with the webhook's own CA bundle; `--force-conflicts`
  makes the apply take ownership of the conflict instead of erroring.

**Order of operations in apply.sh:**

1. Apply MetalLB bundle (CRDs + deployments + webhooks)
2. Wait for `kubectl get pods -n metallb-system -l component=controller` to be 1/1
3. Apply `IPAddressPool` + `L2Advertisement` (this is what would fail
   with "no matches for kind" or "Internal error occurred: failed
   calling webhook" if step 1's CRDs aren't registered yet)
4. Apply Traefik (DS + RBAC + IngressClass + 5 Ingresses + Service of type LoadBalancer)
5. Wait for `kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` to be non-empty

The webhook wait between step 1 and step 3 is critical — MetalLB's
webhook must be up before the IPAddressPool can be validated.

---

## Apply

```bash
cd stages/stage2/set4-metallb-traefik
./scripts/apply.sh
```

The script (8 steps):
1. Rebuilds the frontend image with Set 4's VITE\_\* URLs (no port
   number — MetalLB gives a real IP that the browser resolves via
   `/etc/hosts` or nip.io)
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts
4. Applies: apps + infra (10 components, all ClusterIP)
5. Applies: 3 init jobs (DB schemas + seed)
6. Applies: MetalLB install → wait for controller → IPAddressPool
7. Applies: Traefik (DaemonSet + RBAC + IngressClass + 5 Ingresses + 1 LoadBalancer Service)
8. Prints the MetalLB-assigned IP and the `/etc/hosts` lines to add

After it finishes:

```bash
# Add to /etc/hosts (replace <IP> with the one apply.sh printed):
<IP>  frontend.apollo.local identity.apollo.local flight.apollo.local \
      booking.apollo.local search.apollo.local
```

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **26/26 checks pass**.

| # | Group | What |
|---|---|---|
| 1-3 | Namespaces | apollo-airlines-apps, apollo-airlines-ui, metallb-system |
| 4-13 | Deployments | 10 apps (5 backends + frontend + 3 PG + redis) all Ready |
| 14 | MetalLB controller | `deploy controller` in metallb-system 1/1 |
| 15 | Traefik DaemonSet | `ds traefik` in kube-system has 1+ ready pods |
| 16-18 | Init jobs | init-identity-db, init-flight-db, init-booking-db all succeeded |
| 19 | IPAddressPool | `apollo-pool` in metallb-system exists |
| 20 | Traefik LoadBalancer | Traefik svc has a non-empty `status.loadBalancer.ingress[0].ip` |
| 21 | IngressClass | `traefik` IngressClass registered |
| 22 | Ingress count | ≥5 Ingresses (the 5 app routes) |
| 23-26 | Smoke tests | curl /healthz on identity, /api/flights on flight, / on frontend, full login through the Traefik IP |

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes:
- The 2 app namespaces (`apollo-airlines-apps`, `apollo-airlines-ui`)
- Traefik (DaemonSet + ClusterRole + ClusterRoleBinding + ServiceAccount + IngressClass) in `kube-system`
- MetalLB (`metallb-system` namespace + 5 CRDs)

The teardown order matters: the Traefik cleanup happens **before**
the MetalLB cleanup because the Traefik Service is the thing
holding the MetalLB IP. If MetalLB is gone first, the Traefik
Service just loses its IP and the rest is normal deletion.

---

## Concepts you should be able to answer

1. **What's the difference between `type: NodePort` and `type: LoadBalancer`?** — NodePort allocates a static port on every node (30000-32767) and the cluster's network does the rest. LoadBalancer expects a cloud provider or MetalLB to allocate a real IP from a pool. With NodePort, the port is your access vector (`localhost:30443`). With LoadBalancer, the IP is your access vector (`http://172.18.0.50`).
2. **Why L2 mode instead of BGP?** — kind's docker network has no router, so BGP has nothing to peer with. L2 mode (ARP/NDP) works on any L2 segment, no router config. Production multi-rack on-prem often uses BGP; kind / single-segment labs use L2.
3. **What's an `IPAddressPool`? An `L2Advertisement`?** — Pool = "the IPs MetalLB is allowed to hand out". Advertisement = "how to tell the network these IPs are alive". They're separate because you might have multiple pools and want to advertise only some of them (e.g. "internal pool" stays private, "external pool" gets advertised on BGP).
4. **Why does `apply.sh` use `--server-side --force-conflicts` for the MetalLB bundle?** — `--server-side` for the >256KB last-applied-config limit. `--force-conflicts` because MetalLB's `ValidatingWebhookConfiguration` rotates its own CA, and the first apply will see a conflict on the CA bundle.
5. **What happens if your pool overlaps kind's own IPs?** — ARP for the conflicting IP returns the speaker pod's MAC instead of the node's MAC. Network traffic to the control-plane (kubectl exec, the API server itself) gets routed to the wrong machine. Subtle, painful to debug. Always check `kubectl get nodes -o yaml` and pick a pool range **above** the highest node IP.

---

## What changed for the apps

Nothing. The 6 apps and 4 StatefulSets don't know or care whether
Traefik is reached via NodePort, LoadBalancer, or port-forward. The
Service type change is a property of the Traefik pod's *exposure*,
not of the apps. The frontend's VITE\_\* URLs even drop the `:port`
suffix because the new IP doesn't have a port — Traefik is on the
default HTTP port 80.

---

## Alternative DNS (no /etc/hosts edit)

`apply.sh` prints this tip at the end:

```bash
# Use nip.io: http://frontend.<IP>.nip.io/  (auto-resolves to the IP)
```

`nip.io` is a public DNS service that resolves `172-18-0-50.nip.io`
to `172.18.0.50` (it converts each `.` in the IP to `-`). Combined
with the `Host:` header, this gives you browser access without
touching `/etc/hosts`. Convenient for the smoke test, but not for
production (you don't want to depend on a public DNS).

---

## Previous / Next

- **Previous:** [Set 3: Traefik Ingress + Dashboard](../set3-traefik-dashboard/README.md) — same Traefik on NodePort, plus the Traefik dashboard at `traefik.apollo.local`
- **Next:** [Set 5: Envoy Gateway + MetalLB](../set5-envoy-gateway/README.md) — same MetalLB stack, but Traefik is replaced with the Gateway API + Envoy Gateway v1.5.0
