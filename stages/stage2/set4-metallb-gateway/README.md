---
title: "Stage 2 / Set 4: Envoy Gateway + MetalLB"
description: "Gateway API with Envoy as the data plane, exposed via MetalLB LoadBalancer with a real cluster IP."
---

# Stage 2 / Set 4 — Envoy Gateway + MetalLB

The same Envoy Gateway as Set 3, but with **MetalLB** providing a real
LoadBalancer IP. Now you can hit the Gateway with a real IP, no
port-forward needed.

| | |
|---|---|
| **New concept** | MetalLB L2 mode, IPAddressPool, L2Advertisement, LoadBalancer Services in non-cloud clusters |
| **Access pattern** | `curl -H 'Host: identity.apollo.local' http://172.18.0.50/...` |
| **Controller** | Envoy Gateway v1.2.4 + MetalLB v0.14.5 (L2) |
| **DNS** | `/etc/hosts` (5 entries → 172.18.0.50) OR `nip.io` |
| **Result** | **28/28 verify checks pass** |

---

## Why MetalLB?

In cloud Kubernetes (EKS, GKE, AKS), LoadBalancer Services get a public
IP automatically via the cloud provider's integration. In **kind** (and
in any on-prem cluster), there's no cloud provider, so LoadBalancer
Services stay `<pending>` forever.

**MetalLB** solves this. It runs in the cluster and assigns IPs from a
configured pool. Two modes:
- **Layer 2** (ARP/NDP) — what we use. Simple, works everywhere.
- **BGP** — for real on-prem routers that speak BGP.

---

## Architecture

```
       Browser
         |
         |  HTTP, Host: <svc>.apollo.local
         v
   172.18.0.50  (real cluster IP from MetalLB pool)
         |
         v
   +-----------+         +-----------+
   |  Envoy    |  routes |  Envoy    | (auto-created
   |  Service  |-------->|  proxy    |  by Gateway)
   |  (LB)     |         +-----------+
   +-----------+               |
                               v
                  +----------+ +----------+ +----------+
                  | identity | | frontend | | flight   |  (ClusterIP)
                  +----------+ +----------+ +----------+
                          ^
                          |
                  MetalLB L2 pool:
                  172.18.0.50 – 172.18.0.100
```

MetalLB responds to ARP requests for 172.18.0.50 with the MAC address of
the Envoy Service's backing pod. Traffic flows directly.

---

## Prerequisites

- A kind cluster with the **172.18.0.0/16** docker network (default)
- The IP pool range `172.18.0.50–172.18.0.100` must not collide with
  your existing nodes (the control-plane is usually `.2`, workers `.3`–`.4`)

```bash
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml
```

---

## Apply

```bash
cd stages/stage2/set4-metallb-gateway
./scripts/apply.sh
```

The script:
1. Rebuilds the frontend image with Set 4's VITE\_\* URLs (no port)
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts → apps + infra → init jobs
4. Applies MetalLB install (server-side) + IPAddressPool + L2Advertisement
5. Applies Envoy Gateway install + GatewayClass + Gateway + HTTPRoutes
6. Waits for the Gateway to become `Programmed`
7. Waits for MetalLB to assign a LoadBalancer IP
8. Prints the assigned IP and `/etc/hosts` instructions

After the script finishes, set up local DNS:

```bash
# Use the IP printed by apply.sh, e.g. 172.18.0.50:
172.18.0.50  frontend.apollo.local identity.apollo.local flight.apollo.local \
              booking.apollo.local search.apollo.local
```

**Or, skip the `/etc/hosts` edit entirely** with nip.io:

```bash
curl -H 'Host: frontend.apollo.local' http://frontend.172-18-0-50.nip.io/
```

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **28/28 checks pass**. The verify script auto-discovers the
MetalLB-assigned IP and uses it for the smoke tests — no port-forward
needed.

Manual smoke test (with the printed IP):

```bash
ENVOY_IP=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -H 'Host: identity.apollo.local' "http://$ENVOY_IP/healthz"
curl -H 'Host: flight.apollo.local'   "http://$ENVOY_IP/api/flights"
open "http://frontend.apollo.local/"
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes both `apollo-airlines-*` namespaces, Envoy Gateway, and MetalLB
(including the `metallb-system` namespace).

---

## What's in here (file map)

```
k8s/
├── config/                       # VITE_* with apollo.local (no port)
├── serviceaccounts/accounts.yaml
├── networkpolicies/               # reference only
├── apps/                          # same as Set 1 (ClusterIP)
├── jobs/                          # 3 init DB jobs
├── metallb/                       # ← NEW vs Set 3
│   ├── 00-metallb-native.yaml     # bundled upstream install (~1900 lines)
│   └── 01-ip-pool.yaml            # IPAddressPool + L2Advertisement
└── gateway/                       # same as Set 3
    ├── 00-envoy-gateway-install.yaml
    ├── 00a-gatewayclass.yaml
    ├── 01-gateway.yaml
    ├── 01a-referencegrant.yaml
    ├── 02-httproute-identity.yaml
    ├── ... (4 more HTTPRoutes)
    └── 07-httproute-frontend.yaml
```

---

## Important caveats (read this!)

### `--server-side --force-conflicts` for MetalLB

MetalLB's webhook manages its own CA bundle (for cert rotation). When
applying the install.yaml, the webhook has already been registered and
has its own field manager. The apply.sh uses `--force-conflicts` to
overwrite the conflicting field. If you re-run `apply.sh`, the
`--force-conflicts` handles the re-apply without erroring.

### The IPAddressPool range

The default range `172.18.0.50–172.18.0.100` works on a default kind
network. If you customized your kind network, edit `k8s/metallb/01-ip-pool.yaml`.

If you see "no IP assigned" after a few minutes:
```bash
kubectl logs -n metallb-system deploy/controller | tail -20
kubectl get ipaddresspool -A
kubectl get l2advertisement -A
```

Common causes:
- Range overlaps with your kind network's node IPs
- MetalLB controller can't reach the speaker daemonset (check pod status)

### Why we keep `type: LoadBalancer` here

In Set 3, we patched the Envoy Service from `LoadBalancer` to
`ClusterIP`. In Set 4, we **don't** patch it — MetalLB takes over and
assigns an IP from the pool. The Service stays `type: LoadBalancer`.

---

## Concepts you should be able to answer

1. What's the difference between Layer 2 and BGP mode in MetalLB?
2. Why does MetalLB need a pool of IPs?
3. How does the browser actually reach `172.18.0.50` from your laptop? (Hint: ARP, docker networking)
4. What does `L2Advertisement` do that `IPAddressPool` alone doesn't?
5. What would happen if you deleted the `L2Advertisement` but kept the `IPAddressPool`?
6. Why does Set 4 not need port-forward but Set 3 does?

---

## Stage 2 complete

You've now seen all 4 access patterns. The student can compare:

- **Set 1**: cluster-only `NodePort` — no controller, no gateway
- **Set 2**: Traefik + Ingress — the "old" Kubernetes way
- **Set 3**: Envoy Gateway API — the "new" Kubernetes way (with port-forward for dev)
- **Set 4**: Envoy Gateway API + MetalLB — the "new" Kubernetes way (with real IPs)

Next: [Stage 3: Mission Data](../stage3/README.md) — StatefulSets with persistent volumes. The Headless Services created in Stage 2 will be wired to the StatefulSet `serviceName` field.
