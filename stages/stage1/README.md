---
title: "Stage 1: Liftoff — Kubernetes Deployments"
description: "Deploy all 11 services to a kind cluster using Deployments, ConfigMaps, Secrets, and Jobs."
---

# Stage 1: Liftoff

**Goal:** Deploy all application services to a Kubernetes cluster using Deployments, ConfigMaps, Secrets, and Jobs.

## What You'll Learn

- Organize workloads using **namespaces**
- Deploy applications using **Deployments** (no StatefulSets yet — those come in stage 3)
- Use **ConfigMaps** for non-sensitive configuration
- Use **Secrets** for DB passwords and JWT secret
- Run one-time tasks with **Jobs**, scheduled tasks with **CronJobs**
- Access workloads using **port forwarding**

## Services (11 total — all Deployments)

| Service | Port | Type | Database |
|---|---|---|---|
| frontend | 3000 | NodePort | — |
| auth | 8080 | ClusterIP | auth-postgres (Deployment) |
| catalog | 8081 | ClusterIP | catalog-postgres (Deployment) |
| circulation | 8082 | ClusterIP | circulation-postgres (Deployment) |
| notification | 8083 | ClusterIP | notification-redis (Deployment) |
| fines | 8084 | ClusterIP | — |
| auth-postgres | 5432 | ClusterIP | — |
| catalog-postgres | 5432 | ClusterIP | — |
| catalog-redis | 6379 | ClusterIP | — |
| circulation-postgres | 5432 | ClusterIP | — |
| notification-redis | 6380 | ClusterIP | — |

## Prereqs

- kind cluster running (`kind create cluster --name apollo11`)
- kubectl configured

## Deploy

```bash
cd stages/stage1
kubectl apply -k k8s/
```

## Verify

```bash
kubectl get pods -n apollo11
kubectl get svc -n apollo11
```

## Test

```bash
# Port-forward frontend
kubectl port-forward -n apollo11 svc/frontend 3000:3000

# In another terminal
curl http://localhost:3000/health
curl http://localhost:8080/health   # auth
curl http://localhost:8081/health  # catalog
```

## Clean Up

```bash
kubectl delete -k k8s/
```

## Key Concepts

```
Deployment reconciliation:
┌─────────────┐      ┌──────────────┐      ┌─────────┐
│ Deployment  │ ───▶ │ ReplicaSet    │ ───▶ │  Pods   │
│ (desired)   │      │ (ensure N pods)│     │ (running)│
└─────────────┘      └──────────────┘      └─────────┘
```

| Resource | Purpose |
|---|---|
| Namespace | Logical isolation |
| ConfigMap | Non-sensitive config (env vars, port, service URLs) |
| Secret | Sensitive data (DB passwords, JWT secret) |
| Deployment | Declarative pod management with replicas |
| Job | One-time task completion |
| CronJob | Scheduled recurring tasks |

## Note on Storage

Postgres and Redis use **emptyDir** volumes — data is lost when Pods restart. Stage 3 introduces PersistentVolumeClaims and StatefulSets for durable storage.