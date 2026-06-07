---
title: "Stage 1: Liftoff — Kubernetes Deployments"
description: "Deploy all 10 Apollo Airlines components to a kind cluster using Deployments, ConfigMaps, Secrets, and Jobs."
---

# Stage 1: Liftoff

**Goal:** Deploy all 10 components to a Kubernetes cluster using
Deployments, ConfigMaps, Secrets, and Jobs — and understand every field
in every manifest.

## What You'll Learn

| Concept | File(s) | What It Does |
|---|---|---|
| Namespace | `config/namespace.yaml` | Logical isolation boundary |
| ConfigMap | `config/configmap.yaml` | Non-sensitive configuration |
| Secret | `config/secrets.yaml` | Sensitive data (passwords, tokens) |
| Deployment | `infra/**/dep.yaml`, `apps/**/dep.yaml` | Declarative pod management with replicas |
| Service | `infra/**/svc.yaml`, `apps/**/svc.yaml` | Stable network endpoint for pods |
| Job | `jobs/init-*.yaml` | One-time task to completion |
| emptyDir volume | `infra/**/dep.yaml` | Ephemeral storage (cleared on pod restart) |
| Kustomize | `k8s/kustomization.yaml` | Composes all sub-components into one apply |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Namespace: apollo-airlines                                      │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ConfigMap (apollo-airlines-config)  Secret (apollo-airlines-secrets) │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌──infra─────────────────┐  ┌──apps──────────────────────────┐  │
│  │ identity-db    (×1)    │  │  identity   (×2) ─┐           │  │
│  │ flight-db      (×1)   │  │  flight     (×2) ├─ Service   │  │
│  │ booking-db     (×1)   │  │  booking    (×2) │            │  │
│  │ redis          (×1)  │  │  search     (×2) │            │  │
│  └───────────────────────┘  │  notification(×2) │            │  │
│                              │  frontend   (×2) ─┘            │  │
│                              └──────────────────────────────────┘  │
│  ┌──jobs───────────────────────────────────────────────────────┐  │
│  │  init-identity-db  init-flight-db  init-booking-db         │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## The Reconciliation Loop

Kubernetes never directly creates Pods. A Deployment manages the loop:

```
┌────────────┐      ┌───────────────┐      ┌─────────────┐
│ Deployment  │ ───▶ │  ReplicaSet    │ ───▶ │  Pods        │
│ (desired    │      │  (matches     │      │  (running    │
│  state)     │      │   replica     │      │   instances) │
│              │      │   count)      │      │              │
│ spec:        │      │               │      │              │
│  replicas: 2 │ ───▶ │  [pod] [pod]  │ ───▶ │  [●] [●]     │
└────────────┘      └───────────────┘      └─────────────┘
                        └── selector ──────▶ labels: app: identity
```

If a Pod crashes, the ReplicaSet replaces it. If you change `replicas: 3`,
the ReplicaSet creates one more Pod. If you change the container image,
the ReplicaSet rolls out a new version.

---

## All 10 Components

```
┌─────────────────┬────────┬─────────────┬────────────────────────────────┐
│ Service          │  Port  │ Type        │ Backend                         │
├─────────────────┼────────┼─────────────┼────────────────────────────────┤
│ identity-db    │  5432  │ ClusterIP   │ (PostgreSQL 15)                 │
│ flight-db      │  5432  │ ClusterIP   │ (PostgreSQL 15)                 │
│ booking-db     │  5432  │ ClusterIP   │ (PostgreSQL 15)                 │
│ redis          │  6379  │ ClusterIP   │ (Redis 7)                       │
│ identity       │  8080  │ NodePort    │ identity-db  →  :30083          │
│ flight         │  8081  │ NodePort    │ flight-db    →  :30081          │
│ booking        │  8082  │ NodePort    │ booking-db   →  :30082          │
│ search         │  8083  │ NodePort    │ flight svc   →  :30084          │
│ notification   │  8084  │ ClusterIP   │ redis (6379)                    │
│ frontend       │  3000  │ NodePort    │ (nginx)      →  :30080          │
└─────────────────┴────────┴─────────────┴────────────────────────────────┘
```

**Why NodePort for backend services?** Stage 1 runs in a kind cluster with no
cloud load balancer. NodePort lets you `curl http://localhost:30083/...` from
the host without `kubectl port-forward`. Stage 2 replaces this with a Traefik
Ingress — NodePort goes away.

**Why is `notification` still ClusterIP?** Nothing outside the cluster calls
notification directly — only the booking service does, via the in-cluster DNS
name. Exposing it externally would be a security smell.

---

## Manifest Structure

```
k8s/
├── config/
│   ├── namespace.yaml       # 1. Create the namespace first
│   ├── configmap.yaml       # 2. Config (non-sensitive)
│   └── secrets.yaml         # 3. Secrets (sensitive)
├── infra/
│   ├── identity-db/
│   │   ├── identity-db-dep.yaml
│   │   └── identity-db-svc.yaml
│   ├── flight-db/
│   │   ├── flight-db-dep.yaml
│   │   └── flight-db-svc.yaml
│   ├── booking-db/
│   │   ├── booking-db-dep.yaml
│   │   └── booking-db-svc.yaml
│   └── redis/
│       ├── redis-dep.yaml
│       └── redis-svc.yaml
├── apps/
│   ├── identity/
│   │   ├── identity-dep.yaml
│   │   └── identity-svc.yaml
│   ├── flight/
│   │   ├── flight-dep.yaml
│   │   └── flight-svc.yaml
│   ├── booking/
│   │   ├── booking-dep.yaml
│   │   └── booking-svc.yaml
│   ├── search/
│   │   ├── search-dep.yaml
│   │   └── search-svc.yaml
│   ├── notification/
│   │   ├── notification-dep.yaml
│   │   └── notification-svc.yaml
│   └── frontend/
│       ├── frontend-dep.yaml
│       └── frontend-svc.yaml
└── jobs/
    ├── identity-init-configmap.yaml
    ├── init-identity-db.yaml
    ├── flight-init-configmap.yaml
    ├── init-flight-db.yaml
    ├── booking-init-configmap.yaml
    └── init-booking-db.yaml
```

Apply order: namespace → config → secrets → infra → apps → jobs

---

## Deploy

### 1. Build the container images

```bash
cd stages/stage1
./scripts/build-images.sh
```

### 2. Apply manifests

```bash
kubectl apply -f k8s/config/
kubectl apply -f k8s/infra/
kubectl apply -f k8s/apps/
kubectl apply -f k8s/jobs/
```

Or use Kustomize:

```bash
kubectl apply -k k8s/
```

---

## Self-Check

```bash
bash /home/darshan/projects/Apollo11/test/stage1_test.sh
```

---

## Access the Services

All five user-facing services are exposed via NodePort. Open the URLs below
in a browser or `curl` them directly from the host (no `port-forward` needed):

| Service        | URL                                            |
|----------------|------------------------------------------------|
| Frontend (UI)  | http://localhost:30080                          |
| Identity (API) | http://localhost:30083                          |
| Flight (API)   | http://localhost:30081                          |
| Booking (API)  | http://localhost:30082                          |
| Search (API)   | http://localhost:30084                          |

> The NodePort range is mapped in `stages/ignition/kind-config.yaml` and
> `kind-config-single.yaml` via `extraPortMappings`. If you created the
> cluster with a different config, the host-side ports won't be reachable.

**Quick smoke test:**

```bash
# Login
curl -X POST http://localhost:30083/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'

# List flights
curl http://localhost:30081/api/flights
```

Cluster-internal services (DBs, Redis) are still ClusterIP — reach them
via `kubectl port-forward` or `kubectl exec` if you need to poke around.

**Login:**

```bash
curl -X POST http://localhost:8080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
```

---

## Clean Up

```bash
kubectl delete namespace apollo-airlines
```

---

## Key Takeaways

```
apiVersion + kind           → What type of object is this?
metadata.name + namespace   → Unique identity within the cluster
spec.selector               → How Services/Deployments find their Pods
spec.replicas               → How many copies to keep running
spec.template.metadata.labels → Labels applied to every Pod created
containers[].env            → Inline env vars (secrets, exact values)
containers[].envFrom        → ConfigMap as env var source (bulk config)
containers[].volumeMounts   → Where to attach a volume inside the container
volumes[].emptyDir          → Ephemeral storage (lost on pod restart)
Service.spec.type           → ClusterIP (internal) / NodePort (dev) / LoadBalancer (cloud)
Job.spec.backoffLimit        → How many times to retry a failed Job
ConfigMap.data              → Non-sensitive key-value pairs
Secret.stringData           → Sensitive data (base64-encoded at rest)
Kustomize.resources          → Compose multiple dirs into one apply
```

---

## What's Next

Stage 2 adds **namespace isolation, DNS-based service discovery,
NetworkPolicies, and Ingress** — services can only talk to whitelisted peers,
and frontend becomes accessible via hostname.

**Before moving on, make sure you can answer:**
1. What happens to a Deployment's Pods when you change the image tag?
2. What's the difference between `env:` and `envFrom:`?
3. Why does the init Job need a volume to mount the ConfigMap?
4. What would break if you set `replicas: 0` on the identity Deployment?
5. Why does each service have its own PostgreSQL database instead of sharing one?