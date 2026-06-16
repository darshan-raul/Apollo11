---
title: "Stage 2: Networking & Access — 5 Manifest Sets"
description: "Same 10 components, 5 different ways to expose them — NodePort, Ingress, Ingress+dashboard, LoadBalancer+MetalLB, Gateway API+MetalLB."
---

# Stage 2: Networking & Access

The workloads are the same in every set. What changes is **how traffic gets
to them**. Each set is a self-contained, from-scratch deployment. Pick one,
apply it, verify, tear down, move on.

| Set | Access mechanism | Verify result |
|-----|------------------|---------------|
| 1. **Baseline** | `NodePort` (30080–30084) — no controller | 25/25 pass |
| 2. **Ingress** | Traefik v3 Ingress + NodePort 30443 | 26/26 pass |
| 3. **Ingress + dashboard** | Traefik v3 + Traefik dashboard via IngressRoute | 27/27 pass |
| 4. **Ingress + MetalLB** | Traefik v3 + MetalLB L2 LoadBalancer | 26/26 pass |
| 5. **Gateway API + MetalLB** | Envoy Gateway + MetalLB L2 LoadBalancer | 29/29 pass |

---

## The progression

Each set introduces **one new concept** on top of the previous:

```
Set 1               Set 2               Set 3                Set 4                 Set 5
─────               ─────               ─────                ─────                 ─────
NodePort            + Ingress           + Dashboard          + LoadBalancer        + Gateway API
no controller       Traefik IngressClass Traefik api@internal  type=LoadBalancer      Envoy GatewayClass=eg
host header         Host-based routing  IngressRoute to      MetalLB IP pool       GatewayClass + Gateway
on direct pods      via Traefik DS      controller-internal   (L2) gives real IP     + EnvoyProxy + 6 HTTPRoutes
```

**Set 1** teaches the lowest layer — `Service type: NodePort`, kubelet routes
to pods directly. No HTTP routing, no controller.

**Set 2** adds an L7 HTTP layer in front of plain NodePorts. One
Traefik DaemonSet, one NodePort (30443), five Ingresses with `Host:`
matching. The student sees how a single port becomes five services.

**Set 3** keeps set 2's edge access and adds the Traefik dashboard
behind it. The dashboard is served by Traefik's internal `api@internal`
service — an IngressRoute routes `traefik.apollo.local` to it. Proves
Ingress can route to non-Service backends.

**Set 4** swaps the Traefik Service from `NodePort` to `LoadBalancer`
and adds MetalLB in L2 mode. Now the user has a real cluster IP
(172.18.0.50ish) on the docker network. The browser hits `*.apollo.local`
directly — no NodePort mapping, no port-forward.

**Set 5** swaps Traefik for Envoy Gateway (the new standard) on the
same MetalLB IP. Introduces GatewayClass, Gateway, HTTPRoute,
ReferenceGrant, and EnvoyProxy. The EnvoyProxy `envoyService.type:
LoadBalancer` is what makes MetalLB do the work — no port-forward,
no NodePort.

---

## Layout (each set is the same shape)

```
stages/stage2/
├── code/                        # shared source for all sets (no code changes in stage 2)
├── set1-baseline/               # ← Set 1, NodePort
├── set2-ingress/                # ← Set 2, Traefik + NodePort
├── set3-traefik-dashboard/      # ← Set 3, Traefik + dashboard
├── set4-metallb-traefik/        # ← Set 4, Traefik + MetalLB
└── set5-envoy-gateway/          # ← Set 5, Envoy Gateway + MetalLB
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
│   ├── ingress/   (sets 2, 3, 4) # Traefik DaemonSet + Ingresses (+ dashboard in set 3)
│   ├── gateway/   (set 5)        # Envoy Gateway install + Gateway + HTTPRoutes
│   └── metallb/   (sets 4, 5)    # MetalLB install + IP pool + L2 advertisement
└── scripts/
    ├── apply.sh                  # build images, apply manifests in order
    ├── teardown.sh               # delete namespaces + controller
    ├── verify.sh                 # battery of checks (25-29 per set)
    └── build-images.sh           # per-set frontend VITE_* URLs
```

---

## Shared between all sets

### 2 namespaces
- `apollo-airlines-apps` — identity, flight, booking, search, notification, identity-db, flight-db, booking-db, redis, init jobs
- `apollo-airlines-ui`   — frontend

### Hostnames (sets 2-5)
- `frontend.apollo.local`
- `identity.apollo.local`
- `flight.apollo.local`
- `booking.apollo.local`
- `search.apollo.local`
- `traefik.apollo.local` (set 3 only)

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
- See [set 1 README](../set1-baseline/README.md#about-networkpolicies) for the full story

### Frontend image rebuild
The VITE\_\* env vars (frontend's API URLs) are baked at build time. Each
set rebuilds the frontend image with its own URL pattern. Run `apply.sh`
once and it handles both the build and the image load.

---

## Set-by-set summary

### [Set 1: Baseline (NodePort)](../set1-baseline/README.md)
**Access pattern:** 5 NodePort services (30080-30084), hit directly from host.
**Teaches:** Namespace isolation, FQDN service discovery, Headless Service,
ServiceAccount, NetworkPolicy (as reference).

### [Set 2: Traefik Ingress](../set2-ingress/README.md)
**Access pattern:** Traefik v3 IngressController (DaemonSet on control-plane)
listens on NodePort 30443. Host header routing.
**Teaches:** `Ingress` resource, `IngressClass`, controller selection
(cluster-scoped, watches Ingresses, creates Traefik config).

### [Set 3: Traefik + dashboard](../set3-traefik-dashboard/README.md)
**Access pattern:** Same edge access as Set 2; the Traefik dashboard
itself is exposed at `traefik.apollo.local:30443` via an IngressRoute
to the controller's internal `api@internal` service.
**Teaches:** IngressRoute (Traefik CRD), how Ingress can route to
controller-internal services, what the static config does to Traefik.

### [Set 4: Traefik + MetalLB](../set4-metallb-traefik/README.md)
**Access pattern:** Same Traefik as Sets 2/3, but the Service is now
`type: LoadBalancer` and MetalLB v0.14 assigns a real IP from
172.18.0.50–100. No NodePort, no host-port mapping. The browser hits
the IP directly via `/etc/hosts` or nip.io.
**Teaches:** `Service type: LoadBalancer`, MetalLB L2 mode,
IPAddressPool, L2Advertisement, ARP-based service discovery in kind.

### [Set 5: Envoy Gateway + MetalLB](../set5-envoy-gateway/README.md)
**Access pattern:** Envoy Gateway (controller + auto-created Envoy proxy)
on top of MetalLB. EnvoyProxy sets `envoyService.type: LoadBalancer`
which lets MetalLB assign a real IP. No NodePort, no port-forward.
**Teaches:** GatewayClass, Gateway, HTTPRoute, ReferenceGrant (for
cross-namespace frontend route), `parentRef.namespace`, EnvoyProxy.

---

## Running them in sequence

```bash
# Cluster (one-time, for any set)
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml

# Each set: apply, verify, teardown
cd stages/stage2/set1-baseline && ./scripts/apply.sh && ./scripts/verify.sh && ./scripts/teardown.sh
cd ../set2-ingress           && ./scripts/apply.sh && ./scripts/verify.sh && ./scripts/teardown.sh
cd ../set3-traefik-dashboard && ./scripts/apply.sh && ./scripts/verify.sh && ./scripts/teardown.sh
cd ../set4-metallb-traefik   && ./scripts/apply.sh && ./scripts/verify.sh && ./scripts/teardown.sh
cd ../set5-envoy-gateway     && ./scripts/apply.sh && ./scripts/verify.sh && ./scripts/teardown.sh
```

Sets 4 and 5 print a MetalLB-assigned IP at the end of `apply.sh`.
Add it to `/etc/hosts` (or use the nip.io form the script prints)
before running `verify.sh`.

---

## Notes on bundling

The large `install.yaml` files for Envoy Gateway and MetalLB are
**bundled in this repo** (offline-friendly, no internet required at
apply time). To fetch a newer version instead:

```bash
# Envoy Gateway (set 5)
curl -o stages/stage2/set5-envoy-gateway/k8s/gateway/00-envoy-gateway-install.yaml \
  https://github.com/envoyproxy/gateway/releases/download/v1.5.0/install.yaml

# MetalLB (sets 4 and 5)
curl -o stages/stage2/set4-metallb-traefik/k8s/metallb/00-metallb-native.yaml \
  https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

See [NOTES.md](NOTES.md) for the version-sweep results that chose v1.5.0
for Envoy Gateway.

---

## What comes next (Stage 3)

StatefulSets with persistent volumes. The Headless Services created in
Stage 2 will be wired to the StatefulSet `serviceName` field. Init jobs
become init containers. PVCs (1Gi) per pod.
