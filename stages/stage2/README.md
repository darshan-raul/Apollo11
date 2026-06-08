---
title: "Stage 2: Networking & Access — 4 Manifest Sets"
description: "Same 10 components, 4 different ways to expose them — learn ClusterIP+NodePort, Ingress, Gateway API, and Gateway API with MetalLB."
---

# Stage 2: Networking & Access

The workloads are the same in every set. What changes is **how traffic gets
to them**. Each set is a self-contained, from-scratch deployment. Pick one,
apply it, verify, tear down, move on.

| Set | Access mechanism | Verify result |
|-----|------------------|---------------|
| 1. **Baseline** | `NodePort` (30080–30084) — no controller | 25/25 pass |
| 2. **Ingress** | Traefik v3 Ingress + NodePort 30443 | 25/25 pass |
| 3. **Gateway API (port-forward)** | Envoy Gateway + auto ClusterIP, port-forward from host | 26/26 pass |
| 4. **Gateway API + MetalLB** | Envoy Gateway + MetalLB L2 LoadBalancer | 28/28 pass |

---

## The progression

```
Set 1 (NodePort)            Set 2 (Ingress)              Set 3 (Gateway API)         Set 4 (Gateway + MetalLB)
─────────────────            ────────────────              ──────────────────         ─────────────────────
                                                                                          
kubectl get svc              curl -H 'Host:...'           kubectl port-forward        curl -H 'Host:...'
curl http://:30083           http://:30443                http://:8888                http://172.18.0.50
                                                                                          
Direct port-mapping          Traefik ingress-class        Envoy GatewayClass=eg       Same, but real IP
no controller                "traefik"                    no service type override    MetalLB L2 pool
no gateway                   5 Ingresses                  6 HTTPRoutes + ReferenceGrants  same Gateway
```

**Why this matters:** The student experiences three real production patterns
(Ingress, Gateway API, Gateway+LoadBalancer) and the only difference
between them is the "edge" object. The workloads don't change.

---

## Layout (each set is the same shape)

```
stages/stage2/
├── code/                        # shared source for all sets (no code changes in stage 2)
├── set1-baseline/               # ← Set 1, already shipped
├── set2-ingress/                # ← Set 2
├── set3-gateway-nodeport/       # ← Set 3
└── set4-metallb-gateway/        # ← Set 4
```

Each `setN-*/` directory is self-contained:

```
setN-*/
├── README.md                    # set-specific concepts and steps
├── k8s/
│   ├── config/                   # 2 namespaces, configmap, secrets
│   ├── serviceaccounts/          # 13 SAs (1 per workload + 3 init jobs)
│   ├── networkpolicies/          # reference only — kindnet doesn't enforce
│   ├── apps/                     # 6 app services + 4 infra + 4 headless SVCs
│   ├── jobs/                     # 3 init DB jobs
│   ├── ingress/   (set 2)       # Traefik DaemonSet + Ingresses
│   ├── gateway/   (sets 3, 4)    # Envoy Gateway install + Gateway + HTTPRoutes
│   └── metallb/   (set 4)       # MetalLB install + IP pool + L2 advertisement
└── scripts/
    ├── apply.sh                  # build images, apply manifests in order
    ├── teardown.sh               # delete namespaces + controller
    ├── verify.sh                 # battery of checks (25–28 per set)
    └── build-images.sh           # per-set frontend VITE_* URLs
```

---

## Shared between all sets

### 2 namespaces
- `apollo-airlines-apps` — identity, flight, booking, search, notification, identity-db, flight-db, booking-db, redis, init jobs
- `apollo-airlines-ui`   — frontend

(Was 3 in the SPEC. Collapsed to 2 — infra lives with apps. See
[decision in the master discussion](#).)

### 5 hostnames (Sets 2-4)
- `frontend.apollo.local`
- `identity.apollo.local`
- `flight.apollo.local`
- `booking.apollo.local`
- `search.apollo.local`

### Headless Services for every DB
- `identity-db-headless`, `flight-db-headless`, `booking-db-headless`, `redis-headless`
- `clusterIP: None` — DNS returns pod IPs directly. Used in Stage 3 (StatefulSets).

### ServiceAccounts
- One SA per workload: identity, flight, booking, search, notification, frontend, identity-db, flight-db, booking-db, redis
- Three more for the init jobs: init-identity-db, init-flight-db, init-booking-db
- No `Role`/`RoleBinding` yet — those arrive in Stage 8 (Command Module, RBAC)

### NetworkPolicies
- Manifests are provided for reference under `k8s/networkpolicies/`
- **NOT applied by `apply.sh`** — the default `kindnet` CNI does not enforce them
- See [set1 README](../set1-baseline/README.md#about-networkpolicies) for the full story

### Frontend image rebuild
The VITE\_\* env vars (frontend's API URLs) are baked at build time. Each
set rebuilds the frontend image with its own URL pattern. Run `apply.sh`
once and it handles both the build and the image load.

---

## Set-by-set summary

### [Set 1: Baseline (NodePort)](../set1-baseline/README.md)
**Access pattern:** 5 NodePort services (30080-30084), hit directly from host.
**Teaches:** Namespace isolation, FQDN service discovery (turned out
unnecessary with 2 namespaces), Headless Service, ServiceAccount,
NetworkPolicy (as reference).

### [Set 2: Traefik Ingress](../set2-ingress/README.md)
**Access pattern:** Traefik v3 IngressController (DaemonSet on control-plane)
listens on NodePort 30443. Host header routing.
**Teaches:** `Ingress` resource, `IngressClass`, controller selection
(cluster-scoped, watches Ingresses, creates Envoy/Traefik config).

### [Set 3: Envoy Gateway API](../set3-gateway-nodeport/README.md)
**Access pattern:** Envoy Gateway (controller + auto-created Envoy proxy).
Auto-created Service is ClusterIP, so we use `kubectl port-forward`.
**Teaches:** GatewayClass, Gateway, HTTPRoute, ReferenceGrant (for
cross-namespace frontend route), `parentRef.namespace` for cross-namespace
attachment.

### [Set 4: Envoy Gateway + MetalLB](../set4-metallb-gateway/README.md)
**Access pattern:** Same as Set 3, but MetalLB v0.14 assigns a real
LoadBalancer IP from a 172.18.0.50–100 pool. The Envoy Service stays
`type: LoadBalancer` (no patching needed).
**Teaches:** MetalLB L2 mode, IPAddressPool, L2Advertisement, how
LoadBalancer Services actually get IPs in non-cloud clusters.

---

## Running them in sequence

```bash
# Cluster (one-time, for any set)
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml

# Set 1
cd stages/stage2/set1-baseline && ./scripts/apply.sh && ./scripts/verify.sh
./scripts/teardown.sh

# Set 2
cd ../set2-ingress && ./scripts/apply.sh && ./scripts/verify.sh
./scripts/teardown.sh

# Set 3 — needs port-forward in another terminal
cd ../set3-gateway-nodeport && ./scripts/apply.sh
# In another terminal:
kubectl port-forward -n envoy-gateway-system \
  $(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}') 8888:80
./scripts/verify.sh
./scripts/teardown.sh

# Set 4 — apply prints the MetalLB IP
cd ../set4-metallb-gateway && ./scripts/apply.sh && ./scripts/verify.sh
./scripts/teardown.sh
```

---

## Notes on bundling

The large `install.yaml` files for Envoy Gateway and MetalLB are
**bundled in this repo** (offline-friendly, no internet required at
apply time). To fetch a newer version instead:

```bash
# Envoy Gateway
curl -o stages/stage2/set3-gateway-nodeport/k8s/gateway/00-envoy-gateway-install.yaml \
  https://github.com/envoyproxy/gateway/releases/download/v1.2.4/install.yaml

# MetalLB
curl -o stages/stage2/set4-metallb-gateway/k8s/metallb/00-metallb-native.yaml \
  https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

---

## What comes next (Stage 3)

StatefulSets with persistent volumes. The Headless Services created in
Stage 2 will be wired to the StatefulSet `serviceName` field. Init jobs
become init containers. PVCs (1Gi) per pod.
