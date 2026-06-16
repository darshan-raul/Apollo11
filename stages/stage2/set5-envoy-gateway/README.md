---
title: "Stage 2 / Set 2: Traefik Ingress"
description: "Host-based routing via Traefik v3 Ingress, exposed on NodePort 30443."
---

# Stage 2 / Set 2 — Traefik Ingress

The same 10 components, but now exposed via a **Traefik IngressController**.
The frontend, identity, flight, booking, and search services are no
longer NodePort — they are **ClusterIP**, and Traefik routes external
traffic to them based on the `Host:` header.

| | |
|---|---|
| **New concept** | `Ingress` resource, `IngressClass`, controller selection |
| **Access pattern** | `curl -H 'Host: identity.apollo.local' http://localhost:30443/...` |
| **Controller** | Traefik v3.1 (DaemonSet on control-plane) |
| **DNS** | `/etc/hosts` (5 entries → 127.0.0.1) |
| **Result** | **25/25 verify checks pass** |

---

## Architecture

```
       Browser
         |
         |  HTTP, Host: <svc>.apollo.local
         v
   +-----------+
   |  Traefik  |  (DaemonSet on control-plane, hostPort 30443)
   +-----------+
         |
         |  Routes by hostname
         |
   +---------+    +----------+    +---------+
   |identity |    | frontend |    | flight  |  ... (5 ClusterIP Services)
   +---------+    +----------+    +---------+
         ^
         |
    /etc/hosts resolves *.apollo.local → 127.0.0.1
```

---

## Prerequisites

- A kind cluster (any of the ignition configs work)
- Container images for the 6 services built and loaded into kind

```bash
# If you haven't already:
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml

# The apply.sh below rebuilds and loads the frontend image
# with the Set 2 URLs (apollo.local:30443).
```

---

## Apply

```bash
cd stages/stage2/set2-ingress
./scripts/apply.sh
```

The script:
1. Rebuilds the frontend image with Set 2's VITE\_\* URLs
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts → apps + infra → init jobs → Traefik
4. Prints the `/etc/hosts` lines to add

After it finishes, set up the local DNS:

```bash
# Add to /etc/hosts (or use sudo tee):
127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \
            booking.apollo.local search.apollo.local
```

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **25/25 checks pass** (deployments Ready, init jobs Completed, Traefik DS Ready, 5 Ingresses, 4 smoke tests).

Manual smoke test:

```bash
# Login returns a real JWT
curl -H 'Host: identity.apollo.local' http://localhost:30443/api/users/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'

# List flights
curl -H 'Host: flight.apollo.local' http://localhost:30443/api/flights

# Frontend UI
open http://frontend.apollo.local:30443
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes both `apollo-airlines-*` namespaces and the Traefik controller.

---

## What's in here (file map)

```
k8s/
├── config/
│   ├── 00-namespaces.yaml        # 2 namespaces (apps, ui)
│   ├── configmap.yaml            # VITE_* with apollo.local:30443
│   └── secrets.yaml
├── serviceaccounts/accounts.yaml # 13 SAs
├── networkpolicies/              # reference only (kindnet doesn't enforce)
├── apps/                         # 6 app + 4 infra, all ClusterIP now
├── jobs/                         # 3 init DB jobs
└── ingress/                      # ← NEW vs Set 1
    ├── 00-traefik-rbac-and-class.yaml
    ├── 01-traefik-daemonset.yaml
    ├── 02-ingress-frontend.yaml
    ├── 03-ingress-identity.yaml
    ├── 04-ingress-flight.yaml
    ├── 05-ingress-booking.yaml
    └── 06-ingress-search.yaml
```

---

## Concepts you should be able to answer

1. What's the difference between an `Ingress` and an `IngressClass`?
2. Why did we have to specify `ingressClassName: traefik` on every Ingress?
3. Why a `DaemonSet` on the control-plane (and not a `Deployment`)?
4. How does Traefik know which Service to forward to when you send a request to `identity.apollo.local:30443`?
5. What would happen if you forgot to add `127.0.0.1 frontend.apollo.local` to `/etc/hosts`?

---

## Next set

[Set 3: Envoy Gateway API (port-forward)](../set3-gateway-nodeport/README.md) — same edge concepts, but using Gateway API CRDs and an Envoy data plane.
