---
title: "Stage 2 / Set 1: Baseline"
description: "Two namespaces, NetworkPolicies, ServiceAccounts, Headless Services — services still exposed via NodePort."
---

# Stage 2 / Set 1 — Baseline (no Ingress controller)

This is the starting point. Same workloads as Stage 1, but split across
two namespaces, with `ServiceAccount` per workload, `NetworkPolicy` per
service, and a **Headless Service** for every database. The
`frontend`/`identity`/`flight`/`booking`/`search` services are still
exposed via `NodePort` — no Ingress controller yet.

| | |
|---|---|
| **New concept** | Namespace isolation, ServiceAccount, Headless Service, NetworkPolicy (reference only) |
| **Access pattern** | `http://localhost:30083/...` (NodePort) — same as Stage 1 |
| **Controller** | None |
| **DNS** | None (NodePort uses port numbers) |

> **About NetworkPolicies:** The default kind CNI (`kindnet`) does **not**
> enforce NetworkPolicy. The manifests under `k8s/networkpolicies/` are
> kept as reference material — apply them with
> `kubectl apply -f k8s/networkpolicies/` to study the policy model, but
> in this cluster they are no-ops without a CNI like Calico or Cilium.
> The base `apply.sh` does **not** apply them.

---

## Layout

```
apollo-airlines-apps   identity, flight, booking, search, notification,
                       identity-db, flight-db, booking-db, redis,
                       3 init jobs
apollo-airlines-ui     frontend
```

Everything that needs to talk to each other lives in the same namespace,
so backend-to-backend calls use **short service names** (`identity-db`,
`flight`, `redis`, etc.). The browser hits the frontend via
`http://localhost:30080`, and the frontend's VITE\_\* env vars point at
each service's NodePort (30081–30084).

---

## Prerequisites

Stage 1 cluster and images must exist:

```bash
# Cluster (from ignition)
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml
# or:
kind create cluster --name apollo11-dev --config stages/ignition/kind-config-single.yaml

# Images
cd stages/stage2
../stage1/scripts/build-images.sh --skip-kind-load
kind load docker-image apollo11/identity:latest --name apollo11
kind load docker-image apollo11/flight:latest --name apollo11
kind load docker-image apollo11/booking:latest --name apollo11
kind load docker-image apollo11/search:latest --name apollo11
kind load docker-image apollo11/notification:latest --name apollo11
kind load docker-image apollo11/frontend:latest --name apollo11
```

> Tip: the `apply.sh` script below does the image loading for you.

---

## Apply

```bash
cd stages/stage2/set1-baseline
./scripts/apply.sh
```

Or step-by-step:

```bash
kubectl apply -f k8s/config/         # 2 namespaces, configmap, secrets
kubectl apply -f k8s/serviceaccounts/
# k8s/networkpolicies/ NOT applied — see note above
kubectl apply -f k8s/apps/           # 6 app services + 4 infra + 4 headless SVCs
kubectl apply -f k8s/jobs/          # 3 init DB jobs
```

Wait for everything to come up:

```bash
kubectl get pods -A | grep apollo-airlines
# expect 2/2 on each app, 1/1 on each infra, 1/1 on each init job
```

---

## Verify

```bash
# 2 namespaces exist
kubectl get ns | grep apollo-airlines

# 10 deployments, 14 services (10 normal + 4 headless), 3 init jobs
kubectl get deploy -A | grep apollo-airlines | wc -l   # 10
kubectl get svc -A    | grep apollo-airlines | wc -l   # 14
kubectl get jobs -A   | grep init-                    # 3

# Init jobs completed
kubectl get jobs -A | grep init-
# expect: COMPLETIONS 1/1 for init-identity-db, init-flight-db, init-booking-db

# (Optional) NetworkPolicies — NOT applied by default; see note above
# kubectl apply -f k8s/networkpolicies/   # then: kubectl get netpol -A

# Headless Services for DBs
kubectl get svc -A | grep headless
# expect: identity-db-headless, flight-db-headless, booking-db-headless, redis-headless

# Smoke test
curl -X POST http://localhost:30083/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
# expect: 200 + JWT token
```

Or just run the bundled verifier:

```bash
./scripts/verify.sh
```

---

## Teardown

```bash
cd stages/stage2/set1-baseline
./scripts/teardown.sh
```

Removes both namespaces and everything inside.

---

## What's in here (file map)

```
k8s/
├── config/
│   ├── 00-namespaces.yaml        # 2 namespaces (apps, ui)
│   ├── configmap.yaml            # apps (NS_*) + ui (VITE_*)
│   ├── secrets.yaml              # apps (POSTGRES_PASSWORD, JWT_SECRET) + ui (JWT_SECRET)
│   └── kustomization.yaml
├── serviceaccounts/accounts.yaml # 13 SAs (1 per workload + 3 init jobs)
├── networkpolicies/              # default-deny + per-service allow + DNS egress
├── apps/                         # 6 app services + 4 infra + 4 headless SVCs
│   ├── identity-db/              # {dep, svc, svc-headless}.yaml
│   ├── flight-db/
│   ├── booking-db/
│   ├── redis/
│   ├── identity/                 # NodePort 30083
│   ├── flight/                   # NodePort 30081
│   ├── booking/                  # NodePort 30082
│   ├── search/                   # NodePort 30084
│   ├── notification/             # ClusterIP (internal-only)
│   └── frontend/                 # NodePort 30080, in apollo-airlines-ui
├── jobs/                         # 3 init DB jobs
└── scripts/{apply,teardown,verify}.sh
```

---

## Concepts you should be able to answer

1. Why two namespaces instead of one? (Why not three?)
2. Why does a backend pod use `identity-db:5432` (short name) and not the FQDN? When would the FQDN be required?
3. What's the difference between a `Service` and a `Headless Service`? When would you use each?
4. What does `apps-00-default-deny-ingress` actually do? What happens if you delete it?
5. The `apps-allow-public-ingress` policy uses `tier: public`. Why do the DB and `notification` services NOT have this label? What would happen if you added it?
6. What would break if you forgot to apply `apps-allow-booking-app-to-booking-db`?

---

## Next set

[Set 2: Traefik Ingress](../set2-ingress/README.md) — replace NodePort with
host-based Ingress, the same ten components, but routed by hostname.
