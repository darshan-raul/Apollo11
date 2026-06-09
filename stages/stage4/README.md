---
title: "Stage 4: Flight Control — Probes, Resource Limits, PodDisruptionBudget"
description: "Add liveness/readiness/startup probes, Guaranteed QoS resource governance, PodDisruptionBudgets for booking + frontend, and graceful SIGTERM shutdown to all 10 workloads. Built on the Stage 3 StatefulSets + Stage 2 Envoy+MetalLB access stack."
---

# Stage 4: Flight Control

**Goal:** Make the running workloads **observable, governed, and
shutdown-friendly**. The kubelet needs to know when to restart a
hung process, when to pull a pod from Service endpoints, and when
to give up on a slow-starting container. The scheduler needs CPU
and memory budgets to make placement decisions. Voluntary
disruptions (node drains, cluster upgrades) need a contract that
keeps the UI and the flagship booking service online. And every
container needs to **drain in-flight requests on SIGTERM** rather
than dropping them.

| | |
|---|---|
| **New concept** | startup/liveness/readiness probes, `resources.{requests,limits}`, Guaranteed QoS, `terminationGracePeriodSeconds`, PodDisruptionBudget (`minAvailable`), graceful SIGTERM drain |
| **Workloads changed** | 10 (6 app Deployments + 4 StatefulSets) — probes on apps, resources on all 10, graceful shutdown on all 5 backends + 1 Python service, NGINX probe paths on the frontend |
| **Workloads unchanged** | Envoy Gateway, MetalLB, seed Jobs, NetworkPolicies, ServiceAccounts, ConfigMap, Secret, namespaces |
| **Code changes** | All 5 Go services + FastAPI identity + frontend NGINX config |
| **Verify target** | **129/129 checks pass** (76 Stage 3 baseline + 53 new Stage 4 checks) |

---

## What changed vs Stage 3

### 1. Three distinct probe paths

The single `/healthz` endpoint from Stage 1–3 is split into three:

| Path | Purpose | k8s probe | Returns |
|---|---|---|---|
| `/healthz/startup` | "Process is up and the HTTP server is listening" | `startupProbe` | 200 unconditionally once the server is up |
| `/healthz/live` | "Process is alive (cheap check, no downstream calls)" | `livenessProbe` | 200 unconditionally |
| `/healthz/ready` | "I can handle traffic right now" | `readinessProbe` | 200 if dependency reachable, 503 otherwise |
| `/healthz` | Legacy back-compat | — | 200 |
| `/readyz` | Legacy back-compat | — | 200 |

**Why split them?** With a single endpoint, the kubelet has to use the
same response for "did the process just start?" and "is the process
still healthy?" A `readinessProbe` failure pulls the pod from Service
endpoints (no traffic); a `livenessProbe` failure **restarts the
container**. Conflating them means a temporary DB blip restarts your
app — a self-inflicted outage.

`startupProbe` is a separate window: it runs *during* pod startup and
suppresses liveness checks until it succeeds. With
`failureThreshold: 6 × periodSeconds: 5 = 30s`, the kubelet gives a
slow-starting container 30s to bootstrap before liveness takes over.

For the **DB StatefulSets** we keep the existing `livenessProbe` +
`readinessProbe` (both `pg_isready` / `redis-cli ping`) and **do not
add a `startupProbe`**. Postgres's own `initdb` blocks the main
process from accepting connections until it's done, so `pg_isready`
is already an implicit startup check. Adding a `startupProbe` would
race with the entrypoint and produce false negatives.

For the **frontend** (NGINX), all three probe paths return 200
unconditionally. Readiness on the frontend is "process is alive and
serving", which is what a successful HTTP response from NGINX means.
There is no local DB or Redis to check.

### 2. Guaranteed QoS — `requests == limits` on every container

The kubelet assigns a **Quality of Service class** to every pod:

| QoS | Basis | Eviction under pressure |
|---|---|---|
| `Guaranteed` | `requests == limits` for both CPU and memory | Last to be evicted |
| `Burstable` | `requests` set, `limits > requests` (or limits missing) | Evicted after BestEffort |
| `BestEffort` | No requests/limits | First to be evicted |

Apollo11 uses **Guaranteed** for every pod. The reasoning: the
workloads are small enough that over-committing doesn't buy much
(booking's 200m/256Mi is a tiny slice of a node), and Guaranteed pods
are the last to be killed when the node runs out of memory. Stage 4
is the right time to *teach* Guaranteed QoS — later stages (7: HPA/VPA)
can introduce Burstable when we actually have variable load.

Per-container tiers:

| Tier | CPU req/limit | Memory req/limit |
|---|---|---|
| `identity`, `flight`, `search` (Go) | 100m | 128Mi |
| `booking` (Go, flagship) | 200m | 256Mi |
| `notification` (Go, low-traffic) | 50m | 64Mi |
| `frontend` (NGINX) | 50m | 64Mi |
| `identity-db`, `flight-db`, `booking-db` (PG) | 200m | 256Mi |
| `redis` | 100m | 128Mi |

### 3. `terminationGracePeriodSeconds`

| Workload | Grace period | Why |
|---|---|---|
| All 6 app Deployments | 30s | Enough for the in-flight HTTP drain (Gin's `srv.Shutdown(ctx)` is bounded at 30s) |
| All 4 StatefulSets (PG, redis) | 60s | Postgres needs to checkpoint + flush WAL; Redis AOF rewrite can spike |

When the kubelet wants to stop a pod, it sends SIGTERM and starts a
timer. If the container is still alive when the timer hits, the
kubelet sends SIGKILL. With our graceful-shutdown code in place, the
process has up to the grace period to finish in-flight work and exit
cleanly.

### 4. PodDisruptionBudgets

| PDB | ns | minAvailable | Replicas | Effect |
|---|---|---|---|---|
| `booking-pdb` | apollo-airlines-apps | 1 | 2 | A node drain cannot take booking below 1 ready pod |
| `frontend-pdb` | apollo-airlines-ui | 1 | 2 | A node drain cannot take the UI offline |

PDBs only apply to **voluntary** disruptions (the eviction API).
Involuntary disruptions (node hardware failure, OOMKill) ignore PDBs
and are handled by replica count + re-creation.

### 5. Graceful SIGTERM shutdown

**Go services** (`flight`, `booking`, `search`, `notification`):

```go
srv := &http.Server{Addr: ":" + port, Handler: r}
go srv.ListenAndServe()  // non-blocking

quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
logJSON("INFO", svc, "Received SIGTERM, shutting down gracefully", ...)
srv.Shutdown(ctx)  // stops accepting + drains for up to 30s
db.Close()         // release the connection pool
```

`srv.Shutdown(ctx)` is the Go standard-library primitive for this: it
stops accepting new connections, waits for in-flight requests to
complete, and returns. If `ctx` expires before the drain finishes
(>30s), `Shutdown` returns `context.DeadlineExceeded` and the kubelet
SIGKILLs us — that's the right behavior under load.

**Python/identity** uses `uvicorn`'s built-in handler:

```python
def _log_sigterm(signum, frame):
    log_json("INFO", "identity-service", "Received SIGTERM, ...")
signal.signal(signal.SIGTERM, _log_sigterm)
signal.signal(signal.SIGINT, _log_sigterm)

uvicorn.run(app, host="0.0.0.0", port=8080,
             timeout_graceful_shutdown=30, access_log=False)
```

uvicorn installs its own SIGTERM handler that sets `should_exit=True`,
which triggers a graceful drain. Our handler runs first (Python's
signal-handler chain), just logs, and returns. The `lifespan` context
manager handles DB cleanup.

**NGINX** receives SIGTERM and exits within ~1s. It has no in-flight
state to drain beyond the open connection — we let NGINX handle it.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Apollo11 Cluster                                                    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Pod: booking-xxxxx (Deployment, replicas=2)                  │    │
│  │    QoS: Guaranteed (requests==limits)                         │    │
│  │    terminationGracePeriodSeconds: 30                           │    │
│  │    startupProbe    /healthz/startup   (200, 6×5s = 30s win)   │    │
│  │    livenessProbe   /healthz/live      (200, 10s, fail×3=res)  │    │
│  │    readinessProbe  /healthz/ready     (200/503, 5s, fail×3)   │    │
│  │    resources: { cpu: 200m, memory: 256Mi }                    │    │
│  │    On SIGTERM: log "received SIGTERM" → srv.Shutdown(30s)     │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─ PodDisruptionBudget ─────────────────────────────────────────┐  │
│  │  booking-pdb:   minAvailable=1  (apps ns, 2 replicas)         │  │
│  │  frontend-pdb:  minAvailable=1  (ui    ns, 2 replicas)        │  │
│  │  Status: currentHealthy=2  expectedPods=2  (both satisfied)   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Pod: identity-db-0 (StatefulSet)                             │    │
│  │    QoS: Guaranteed (200m/256Mi == 200m/256Mi)                 │    │
│  │    terminationGracePeriodSeconds: 60                           │    │
│  │    livenessProbe:  pg_isready (exec)                          │    │
│  │    readinessProbe: pg_isready (exec)                          │    │
│  │    NO startupProbe — Postgres' initdb is the implicit start   │    │
│  └──────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Files

```
stages/stage4/
├── code/                       # Snapshot of stage3/code + edits
│   ├── flight/main.go          # 3 new probe handlers + srv.Shutdown
│   ├── booking/main.go         # ditto
│   ├── search/main.go          # ditto
│   ├── notification/main.go    # ditto (ready checks Redis)
│   ├── identity/main.py        # 3 new endpoints + uvicorn timeout_graceful_shutdown
│   └── frontend/
│       ├── nginx.conf          # /healthz/{startup,live,ready} location blocks
│       └── Dockerfile          # COPY nginx.conf into the image
├── k8s/
│   ├── config/                 # Verbatim from stage 3
│   ├── serviceaccounts/        # Verbatim from stage 3
│   ├── networkpolicies/        # Verbatim from stage 3 (reference only)
│   ├── apps/                   # Probes + resources + terminationGracePeriodSeconds
│   │   ├── identity/identity-dep.yaml
│   │   ├── flight/flight-dep.yaml
│   │   ├── booking/booking-dep.yaml       # resources bumped to 200m/256Mi
│   │   ├── search/search-dep.yaml
│   │   ├── notification/notification-dep.yaml  # 50m/64Mi (low tier)
│   │   ├── frontend/frontend-dep.yaml
│   │   ├── identity-db/identity-db-sts.yaml    # +resources (no probes change)
│   │   ├── flight-db/flight-db-sts.yaml        # +resources (no probes change)
│   │   ├── booking-db/booking-db-sts.yaml      # +resources (no probes change)
│   │   └── redis/redis-sts.yaml                # +resources (no probes change)
│   ├── pdb/                    # NEW
│   │   ├── booking-pdb.yaml    # minAvailable=1, 2 replicas
│   │   └── frontend-pdb.yaml   # minAvailable=1, 2 replicas
│   ├── jobs/                   # Verbatim from stage 3
│   ├── gateway/                # Verbatim from stage 3
│   └── metallb/                # Verbatim from stage 3
└── scripts/
    ├── apply.sh                # Stage 3 + apply k8s/pdb/ at step 4
    ├── teardown.sh             # Verbatim from stage 3
    ├── build-images.sh         # Builds stage4/code/ (only code differs)
    └── verify.sh               # 129 checks (76 Stage 3 baseline + 53 Stage 4)
```

---

## Apply / Verify / Teardown

```bash
cd /home/darshan/projects/Apollo11/stages/stage4
./scripts/apply.sh        # ~3 min: builds images, applies 50+ manifests, waits for Gateway
./scripts/verify.sh       # ~30s: 129 checks, prints Passed/Failed count
./scripts/teardown.sh     # ~30s: deletes namespaces + controllers in safe order
```

`apply.sh` exits 0 when the Gateway is Programmed and MetalLB has
assigned an IP. `verify.sh` exits non-zero on any failure. `teardown.sh`
deletes app namespaces first (which drops the PDBs + PVCs), then the
Gateway, then Envoy, then MetalLB — this is the order that avoids
hanging webhooks (see Stage 3 handoff §"Teardown order matters").

---

## Verify (129 checks)

| Group | Count | What it checks |
|---|---|---|
| Stage 3 baseline (namespaces, sts, PVCs, deps, controllers, gateway, routes, smoke) | 76 | Unchanged from Stage 3 — the access stack still works |
| Probes configured on 6 apps | 18 | Each Deployment has startup/live/ready with HTTP path set |
| Probes on 4 sts + no startupProbe | 12 | Each sts has liveness + readiness, no startupProbe |
| Resources on 10 workloads | 10 | requests.{cpu,memory} + limits.{cpu,memory} all set |
| QoS class is Guaranteed on 10 pods | 10 | `.status.qosClass` reports Guaranteed |
| terminationGracePeriodSeconds | 10 | 30s for 6 apps, 60s for 4 sts |
| PodDisruptionBudgets (booking + frontend) | 4 | PDB exists, minAvailable=1, status populated |
| Live probe responses | 18 | curl from inside each pod → 3 probe paths × 6 apps |
| Behavioural demo: graceful shutdown | 2 | Delete a booking pod, follow logs, see "Received SIGTERM" |
| Behavioural demo: frontend restart | 2 | Delete frontend pod, replacement serves /healthz/ready |
| **Total** | **129** | |

---

## Demo: prove the probes actually work

After `apply.sh` finishes:

```bash
# 1. Look at a live pod's probe state
kubectl describe pod -n apollo-airlines-apps -l app=booking | head -40
# Look for:
#   Liveness:  http-get http://:8082/healthz/live  delay=15s period=10s
#   Readiness: http-get http://:8082/healthz/ready delay=5s  period=5s
#   Startup:   http-get http://:8082/healthz/startup delay=0s period=5s

# 2. Hit the probe paths from inside the pod
kubectl exec -n apollo-airlines-apps -l app=booking -- \
  sh -c "wget -q -O- http://127.0.0.1:8082/healthz/{startup,live,ready}"

# 3. Delete a pod — the kubelet creates a new one. Follow the new pod's logs.
kubectl delete pod -n apollo-airlines-apps -l app=booking --wait=false
kubectl logs -n apollo-airlines-apps -l app=booking -f
# You'll see the OLD pod (if you tailed it): "Received SIGTERM, shutting down gracefully"

# 4. Watch a PDB prevent a node drain (only relevant in multi-node)
# With 2 replicas and minAvailable=1, kubectl drain on a node running
# both pods will block until you delete one first (proving the contract).

# 5. Trigger a readiness failure
# Drop a NetworkPolicy or iptables rule that blocks booking's connection
# to booking-db. Within ~15s, the readiness probe starts failing, and
# the pod is removed from Service endpoints:
kubectl exec -n apollo-airlines-apps -l app=booking -- \
  sh -c "wget -q -O- http://127.0.0.1:8082/healthz/ready"
# Returns: {"status":"error","detail":"..."} with 503
```

---

## Lessons learned during build (read this if you're changing this stage)

1. **`kubectl logs --previous <pod>` is unreliable for the SIGTERM
   demo.** When you delete a pod, the API server removes it
   immediately. The `kubectl logs <old-pod> --previous` call returns
   `NotFound` because the old pod is gone. **Fix in verify.sh:** start
   `kubectl logs <pod> --follow` in the background *before* the
   delete, capture the SIGTERM log line, then kill the follower. The
   booking pod's logs in the demo section use this pattern.

2. **NGINX may report Ready before it serves HTTP.** The pod's
   `ready` condition flips based on the readiness probe. The very
   first `kubectl exec ... wget` call can race with NGINX binding the
   port. The verify script retries 30× with 1s sleep and re-fetches
   the pod name each iteration (the API server returns the old
   deleting pod for 1-2s after `kubectl delete --wait=false`).

3. **uvicorn's SIGTERM handling is "baked in" — don't replace it.**
   uvicorn's default signal handler sets `should_exit=True`, which
   triggers a graceful drain via `Server.shutdown()`. If you replace
   the handler with one that calls `sys.exit(0)`, you lose the drain.
   The right pattern: register a *prior* handler that just logs, and
   let uvicorn's handler run.

4. **DB StatefulSets don't need a `startupProbe`.** Postgres' own
   `initdb` is gated by the entrypoint, and `pg_isready` returns
   non-zero until `initdb` is done. A `startupProbe` would race with
   the entrypoint and produce false negatives. The `livenessProbe`
   already covers "is the process healthy".

5. **Guaranteed QoS = `requests == limits`, not "high requests".**
   The class is *Guaranteed* if both fields are set and equal. A pod
   with `requests: {cpu: 100m}, limits: {cpu: 100m}` is Guaranteed.
   A pod with `requests: {cpu: 100m, memory: 256Mi}, limits: {cpu:
   500m, memory: 1Gi}` is Burstable. The verify script asserts
   `qosClass == "Guaranteed"` so a typo in any field fails fast.

6. **PDB status is computed by the controller.** A newly-created PDB
   reports `currentHealthy: 0` until the next reconciliation loop
   (~10s). The verify script tolerates this and retries until
   `currentHealthy >= 1`.

---

## What's next

Stage 5 wraps the manifests in **Helm charts** and **Kustomize
overlays** for environment-specific config (dev/staging/prod) and
adds a **GitHub Actions** workflow. The probe + resource config
we built here becomes a `values.yaml` knob in Helm and a patch in
Kustomize.

**Before moving on, make sure you can answer:**

1. What does each of `startupProbe`, `livenessProbe`, and
   `readinessProbe` do? What happens on failure of each?
2. Why is `requests == limits` classified as Guaranteed QoS? What
   is the alternative and when would you choose it?
3. What's the difference between a `livenessProbe` failure and a
   `readinessProbe` failure from the kubelet's perspective?
4. What is `terminationGracePeriodSeconds`? What happens when the
   timer expires?
5. Why does a `PodDisruptionBudget` only apply to *voluntary*
   disruptions, and what counts as voluntary?
6. What does `srv.Shutdown(ctx)` actually do in Go's
   `net/http`? What if the context expires before all in-flight
   requests complete?
7. Why is uvicorn's default SIGTERM handler the right one to keep?
