---
title: Stage 4 - Flight Control
description: Kubernetes probes, resource limits, QoS classes, PodDisruptionBudgets, and PodPriority
---

# Stage 4 — Flight Control

Probes, resource limits, QoS classes, PodDisruptionBudgets, PodPriority — the operational layer that keeps services running correctly under load.

## What's New

### Code Changes (vs stage3)

All 6 services now expose 3 probe endpoints:

| Endpoint | Behavior |
|---|---|
| `GET /healthz/startup` | 503 for first 5s, then 200 — kubelet waits for process to start |
| `GET /healthz/live` | 200 if process is alive — kubelet pings every 10s, restarts if fails |
| `GET /healthz/ready` | 200 if service can handle traffic (DB/Redis reachable) — kubelet checks before routing |
| `GET /healthz` | Legacy, kept for backwards compatibility |

```go
// Go services (flight, booking, search, notification)
r.GET("/healthz/startup", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })
r.GET("/healthz/live",   func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })
r.GET("/healthz/ready",  func(c *gin.Context) { checkDB(); c.JSON(...) })

// Python/FastAPI (identity)
@app.get("/healthz/startup")
async def healthz_startup(): return JSONResponse({"status": "ok"})
```

Graceful SIGTERM shutdown — services drain in-flight requests before exiting:

```go
// Go: http.Server with Shutdown()
srv := &http.Server{Addr: ":" + port, Handler: r}
go srv.ListenAndServe()
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
srv.Shutdown(context.WithTimeout(context.Background(), 30*time.Second))
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
    port: 8080           # identity: 8080, flight: 8081, booking: 8082, search: 8083, notification: 8084, frontend: 3000+8085
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

#### 4. PriorityClass

`apollo11-app-critical` (value: 100000) assigned to all app pods:

```yaml
priorityClassName: apollo11-app-critical
```

Preempts lower-priority pods when cluster is under pressure.

#### 5. Termination Grace Period

All pods set `terminationGracePeriodSeconds: 30` (apps) or `60` (DBs) — enough time for graceful shutdown and in-flight request completion.

#### 6. PodDisruptionBudget

Frontend and booking services have PDBs ensuring at least 1 replica is available during node drain operations:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: booking-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: booking
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Apollo11 Cluster                                                 │
│                                                                   │
│  PriorityClasses:                                                 │
│  ├─ system-node-critical (value: 2000000)  ← kubelet system pods │
│  ├─ apollo11-app-critical (value: 100000) ← all Apollo11 pods   │
│  └─ cluster-local (value: 0)              ← default              │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Pod: booking-xxxxx                                         │  │
│  │    QoS: Guaranteed (requests==limits)                        │  │
│  │    priorityClass: apollo11-app-critical                     │  │
│  │    startupProbe: /healthz/startup  (30s window)             │  │
│  │    livenessProbe: /healthz/live  (restart on fail)          │  │
│  │    readinessProbe: /healthz/ready (route traffic)            │  │
│  │    resources: cpu=50m-500m, mem=64Mi-256Mi                   │  │
│  │    terminationGracePeriodSeconds: 30                        │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─ PodDisruptionBudget ────────────────────────────────────────┐ │
│  │  booking-pdb: minAvailable=1  (booking deployment, 2 replicas) │ │
│  │  frontend-pdb: minAvailable=1 (frontend deployment, 2 replicas)│ │
│  └──────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Files

```
stage4/
├── code/                          # All 6 services with probe handlers + graceful shutdown
│   ├── booking/main.go            # Go: /healthz/startup/live/ready + SIGTERM
│   ├── flight/main.go             # Go: /healthz/startup/live/ready + SIGTERM
│   ├── search/main.go             # Go: /healthz/startup/live/ready + SIGTERM
│   ├── notification/main.go       # Go: /healthz/startup/live/ready (checks Redis) + SIGTERM
│   ├── identity/main.py           # Python/FastAPI: /healthz/startup/live/ready + SIGTERM
│   └── frontend/
│       ├── probe.go               # Go probe server on :8085
│       ├── Dockerfile             # NGINX + probe server (supervisord)
│       └── supervisord.conf
├── k8s/
│   ├── config/
│   │   ├── namespace.yaml         # 3 namespaces (apollo-airlines-infra/apps/ui)
│   │   ├── serviceaccount.yaml   # 3 SAs
│   │   ├── configmap.yaml         # FQDN service URLs
│   │   ├── secrets.yaml
│   │   ├── ingress.yaml           # Traefik Ingress
│   │   └── priorityclass.yaml    # apollo11-app-critical (value: 100000)
│   ├── infra/
│   │   ├── postgres/              # StatefulSets with probes + limits (3 dbs)
│   │   └── redis/                # StatefulSets with probes + limits
│   ├── apps/                     # Deployments with all 3 probes + PDB
│   │   ├── identity/
│   │   ├── flight/
│   │   ├── booking/              # + booking-pdb.yaml
│   │   ├── search/
│   │   └── notification/
│   └── ui/
│       └── frontend/             # + frontend-pdb.yaml, NGINX + probe sidecar
└── README.md (this file)
```

---

## Deploy

### 1. Build the container images

```bash
cd /home/darshan/projects/Apollo11/stages/stage4
./scripts/build-images.sh
```

### 2. Apply manifests

```bash
kubectl apply -f k8s/config/
kubectl apply -f k8s/infra/
kubectl apply -f k8s/apps/
kubectl apply -f k8s/ui/
```

Or with Kustomize:

```bash
kubectl apply -k k8s/
```

---

## Verification

```bash
# Validate all YAML
kubectl apply --dry-run=server -f k8s/

# Deploy
kubectl apply -f k8s/

# Check pod status and QoS
kubectl get pods -n apollo-airlines-apps -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.qosClass}{"\n"}'

# Watch probe statuses
kubectl get pods -n apollo-airlines-apps -w

# Test startup probe (should return 503 for first 5s, then 200)
curl -s http://identity.apollo-airlines-apps.svc.cluster.local:8080/healthz/startup

# Check PDBs
kubectl get pdb -A

# Check PriorityClass assigned
kubectl get pods -n apollo-airlines-apps -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.priority}{"\n"}'
```

---

## Self-Check

```bash
bash /home/darshan/projects/Apollo11/test/stage4_test.sh
```

---

## Clean Up

```bash
kubectl delete -f k8s/
kubectl delete pvc --all -n apollo-airlines-infra
kubectl delete pvc --all -n apollo-airlines-apps
```

---

## Key Takeaways

```
livenessProbe   → kubelet restarts container on failure (process dead/hung)
readinessProbe  → kubelet removes pod from endpoints (can't handle traffic)
startupProbe    → kubelet waits 30s for startup before liveness takes over

requests        → scheduler uses this to decide which node fits the pod
limits          → kubelet enforces this — pod OOMKilled or CPU throttled

Guaranteed QoS  → requests == limits for both CPU and memory
Burstable       → requests present, but limits > requests
BestEffort      → no requests/limits set

PodPriority     → value determines preemption ranking
preemptionPolicy: PreemptLowerPriority → kills lower-priority pods under pressure

terminationGracePeriodSeconds: 30
  → SIGTERM sent to container → drains in-flight requests → exits
  → If still alive after 30s → SIGKILL

PodDisruptionBudget minAvailable: 1
  → Node drain is blocked if it would violate the PDB
  → Cluster operations (upgrades, maintenance) must respect PDB
```

---

## What's Next

Stage 5 wraps everything in **Helm charts** and **Kustomize overlays** for environment-specific configuration (dev/staging/prod) and GitOps-driven deployment with ArgoCD.

**Before moving on, make sure you can answer:**

1. What happens if a container's liveness probe fails 3 times in a row?
2. Why does a startup probe need to exist alongside a liveness probe?
3. What's the difference between `readinessProbe` and `startupProbe`?
4. Why are resource limits set equal to requests (Guaranteed QoS) in Apollo11?
5. What would happen to in-flight requests if a pod didn't handle SIGTERM?
6. Why does the booking service need a PodDisruptionBudget but the search service doesn't?
7. What does `preemptionPolicy: PreemptLowerPriority` mean in the PriorityClass?