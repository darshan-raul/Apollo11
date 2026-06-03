---
title: Stage 4 - Flight Control
description: Kubernetes probes, resource limits, QoS classes, and PodPriority
---

# Stage 4 — Flight Control

Probes, resource limits, QoS classes, PodPriority — the operational layer that keeps services running correctly under load.

## What's New

### Code Changes (vs stage3)
All 6 services now expose 3 probe endpoints:
- `GET /healthz/startup` — 503 until 5s after boot, then 200
- `GET /healthz/live` — 200 if process is alive
- `GET /healthz/ready` — 200 if service can handle traffic (auth checks DB conn)
- `GET /health` — legacy, kept for backwards compatibility

```go
// Go services: net/http mux
r.GET("/healthz/startup", func(c *gin.Context) { ... })
r.GET("/healthz/live",   func(c *gin.Context) { ... })
r.GET("/healthz/ready",  func(c *gin.Context) { ... })

// Python/FastAPI service
@app.get("/healthz/startup") ...
```

### Kubernetes Changes

#### 1. Probe Strategy
Every pod gets **all three probe types**:

| Probe | Purpose | Failure action |
|---|---|---|
| `startupProbe` | Block traffic during startup (30s window) | Pod not marked ready |
| `livenessProbe` | Detect deadlock / hung process | **Restart container** |
| `readinessProbe` | Detect inability to serve traffic | **Remove from endpoints** |

```yaml
startupProbe:
  httpGet:
    path: /healthz/startup
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 6   # 6 × 5s = 30s max startup time

livenessProbe:
  httpGet:
    path: /healthz/live
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3   # 3 × 10s = 30s hang = restart

readinessProbe:
  httpGet:
    path: /healthz/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

#### 2. Resource Limits
All containers have explicit `resources.requests` and `resources.limits`:

| Tier | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|
| App services | 50m | 500m | 64Mi | 256Mi |
| Frontend | 50m | 200m | 64Mi | 128Mi |
| PostgreSQL | 50m | 500m | 128Mi | 512Mi |
| Redis | 20m | 200m | 32Mi | 128Mi |
| Init container | 10m | 100m | 32Mi | 128Mi |

#### 3. QoS Classes
Kubernetes assigns QoS based on resource requests:

```
┌─────────────────────────────────────────────┐
│ QoS Class          Basis                     │
├─────────────────────────────────────────────┤
│ Guaranteed         requests == limits (both)│
│ Burstable          requests present          │
│ BestEffort         no requests              │
└─────────────────────────────────────────────┘
```

All Apollo11 pods use **Guaranteed** QoS (requests == limits for both CPU and memory).

#### 4. PodPriority
PriorityClass `apollo11-app-critical` (value: 100000) assigned to all app pods:

```yaml
priorityClassName: apollo11-app-critical
```

Preempts lower-priority pods when cluster is under pressure.

#### 5. Termination Grace Period
All pods set `terminationGracePeriodSeconds: 30` (apps) or `60` (DBs) — enough time for graceful shutdown.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Apollo11 Cluster                                     │
│                                                       │
│  ┌─ priority: system-node-critical (value: 2000000)  │
│  ├─ priority: apollo11-app-critical (value: 100000)  │
│  └─ priority: cluster-local (value: 0)               │
│                                                       │
│  Pod scheduling order: system > app-critical > local  │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │  Pod: auth-xxxxx                                 │ │
│  │    QoS: Guaranteed (requests==limits)           │ │
│  │    priorityClass: apollo11-app-critical         │ │
│  │    startupProbe: /healthz/startup (30s window)   │ │
│  │    livenessProbe: /healthz/live (restart on fail)│ │
│  │    readinessProbe: /healthz/ready (route traffic)│ │
│  │    resources: cpu=50m-500m, mem=64Mi-256Mi      │ │
│  │    terminationGracePeriodSeconds: 30           │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Files

```
stage4/
├── code/                     # All 6 services with probe handlers
│   ├── auth/main.py          # FastAPI + psycopg2, /healthz/startup/live/ready
│   ├── catalog/main.go
│   ├── circulation/main.go
│   ├── notification/main.go
│   ├── fines/main.go
│   └── frontend/main.go
├── k8s/
│   ├── config/
│   │   ├── namespace.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   ├── secrets.yaml
│   │   ├── ingress.yaml
│   │   └── priorityclass.yaml   # NEW: PodPriority
│   ├── infra/
│   │   ├── postgres/           # StatefulSets with probes + limits
│   │   └── redis/             # StatefulSets with probes + limits
│   ├── apps/                   # Deployments/StatefulSets with all 3 probes
│   ├── ui/                    # Frontend Deployment with probes
│   └── jobs/
└── README.md (this file)
```

## Verification

```bash
# Validate all YAML
kubectl apply --dry-run=server -f stage4/k8s/

# Deploy
kubectl apply -f stage4/k8s/

# Check pod status and QoS
kubectl get pods -n apollo11-apps -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.qosClass}{"\n"}'

# Watch probe statuses
kubectl get pods -n apollo11-apps -w

# Test startup probe (should return 503 for first 5s, then 200)
curl -s http://auth.apollo11-apps.svc.cluster.local:8080/healthz/startup
```

## What's Next
Stage5 wraps everything in **Helm charts** and **Kustomize overlays** for environment-specific config (dev/staging/prod) and GitOps-driven deployment.