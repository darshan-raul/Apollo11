---
title: "Stage 2 / Set 1: Baseline"
description: "Three namespaces, NetworkPolicies, ServiceAccounts, Headless Services — services still exposed via NodePort."
---

# Stage 2 / Set 1 — Baseline (no Ingress controller)

This is the starting point. Same workloads as Stage 1, but split across
three namespaces, with `ServiceAccount` per workload, `NetworkPolicy` per
service, and a **Headless Service** for every database. The
`frontend`/`identity`/`flight`/`booking`/`search` services are still
exposed via `NodePort` — no Ingress controller yet.

| | |
|---|---|
| **New concept** | Namespace isolation, FQDN service discovery, Headless Service, NetworkPolicy, ServiceAccount |
| **Access pattern** | `http://localhost:30083/...` (NodePort) — same as Stage 1 |
| **Controller** | None |
| **DNS** | None (NodePort uses port numbers) |

---

## Layout

```
apollo-airlines-infra   identity-db, flight-db, booking-db, redis
apollo-airlines-apps    identity, flight, booking, search, notification
apollo-airlines-ui      frontend
```

Backend-to-backend calls use the FQDN `<svc>.<ns>.svc.cluster.local`.
Frontend (browser) still uses `http://localhost:30080` (NodePort).

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
kubectl apply -f k8s/config/         # namespaces, configmap, secrets
kubectl apply -f k8s/serviceaccounts/
kubectl apply -f k8s/networkpolicies/
kubectl apply -f k8s/infra/          # DBs + redis
kubectl apply -f k8s/apps/           # app services
kubectl apply -f k8s/jobs/          # init DB jobs
```

Wait for everything to come up:

```bash
kubectl get pods -A | grep apollo-airlines
# expect 2/2 on each app, 1/1 on each infra
```

---

## Verify

```bash
# All 3 namespaces exist
kubectl get ns | grep apollo-airlines

# 10 deployments, 10 services, 3 init jobs
kubectl get deploy -A | grep apollo-airlines | wc -l   # 10
kubectl get svc -A    | grep apollo-airlines | wc -l   # 10
kubectl get jobs -A   | grep apollo-airlines | wc -l   # 3

# Init jobs completed
kubectl get jobs -A | grep init-
# expect: COMPLETIONS 1/1 for init-identity-db, init-flight-db, init-booking-db

# NetworkPolicies active
kubectl get netpol -A | grep apollo-airlines
# expect: 11+ policies (default-deny + per-service)

# Headless Services for DBs
kubectl get svc -A | grep headless
# expect: identity-db-headless, flight-db-headless, booking-db-headless, redis-headless

# Smoke test
curl -X POST http://localhost:30083/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
# expect: 200 + JWT token
```

---

## Teardown

```bash
cd stages/stage2/set1-baseline
./scripts/teardown.sh
```

Or:

```bash
kubectl delete -f k8s/jobs/
kubectl delete -f k8s/apps/
kubectl delete -f k8s/infra/
kubectl delete -f k8s/networkpolicies/
kubectl delete -f k8s/serviceaccounts/
kubectl delete -f k8s/config/
```

Removes all 3 namespaces and everything inside.

---

## What's in here (file map)

```
k8s/
├── config/
│   ├── 00-namespaces.yaml        # 3 namespaces
│   ├── configmap.yaml            # non-sensitive config
│   ├── secrets.yaml              # passwords, JWT secret
│   └── kustomization.yaml
├── serviceaccounts/              # 1 SA per workload
├── networkpolicies/              # default-deny + per-service allow
├── infra/                        # 4 databases with normal + headless Service
├── apps/                         # 6 app services (5 NodePort + 1 ClusterIP)
├── jobs/                         # 3 init DB jobs
└── kustomization.yaml
```

---

## Concepts you should be able to answer

1. Why three namespaces instead of one?
2. Why does the booking service use FQDN `flight.apollo-airlines-apps.svc.cluster.local` while in Stage 1 it just used `flight:8081`?
3. What's the difference between a `Service` and a `Headless Service`? When would you use each?
4. If you remove the `default-deny` NetworkPolicy, what happens? (Hint: nothing changes — deny is already the default; the policy just makes it explicit and self-documenting.)
5. What would break if you forgot to apply the `allow-booking-to-flight` NetworkPolicy?

---

## Next set

[Set 2: Traefik Ingress](../set2-ingress/README.md) — replace NodePort with
host-based Ingress, the same five services, but routed by hostname.
