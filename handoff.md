---
title: "Apollo11 — Handoff Notes"
description: "Stage 3 complete. End-to-end tested on a fresh kind cluster. Summary for the next agent working on Stage 4 (probes, resource limits, PodDisruptionBudget)."
---

# Apollo11 — Handoff Notes

## Stage 3 Status: COMPLETE (end-to-end tested)

StatefulSets + 1Gi PVCs for all 4 stateful workloads (3 PostgreSQL + redis).
Built on top of the Stage 2 set-4 access stack (Envoy Gateway + MetalLB),
which **persists unchanged for all later stages** (4–11).

| Metric | Result |
|---|---|
| `apply.sh` | exit 0, all 10 steps green |
| `verify.sh` | **53/53** checks pass |
| `teardown.sh` | exit 0, all namespaces + controllers gone |
| Data persistence demo | Row inserted, pod deleted, new pod came back with the row intact |
| Last tested on | fresh kind cluster, kind v0.31.0, k8s v1.35.0 |

**Build artifacts:**
- `stages/stage3/code/` — snapshot of `stages/stage2/code/` (no code changes)
- `stages/stage3/k8s/` — 4 StatefulSets + 4 headless SVCs + 4 ClusterIP SVCs + 6 app Deployments (unchanged) + 3 seed Jobs + 3 seed ConfigMaps + 4 init-script ConfigMaps + gateway/ + metallb/ + serviceaccounts/ + networkpolicies/ + config/
- `stages/stage3/scripts/` — apply.sh, teardown.sh, verify.sh, build-images.sh
- `stages/stage3/README.md` — 478 lines incl. "Lessons learned during build" section
- AGENTS.md Stage 3 section — same level of detail as Stage 2

---

## Stage 3 → Stage 4 baseline (what carries over)

The next agent starts from `stages/stage3/` and produces `stages/stage4/`.
Stage 3's `apply.sh` is the runnable baseline. **Don't rebuild from scratch**
— copy `stages/stage3/` and add Stage 4's changes.

| Layer | Stage 3 state | Carries to Stage 4? |
|---|---|---|
| Access stack (Envoy Gateway + MetalLB) | Gateway Programmed, IP `172.18.0.50`, 6 HTTPRoutes | **YES — verbatim, no changes** |
| ServiceAccounts (13) | 1 per workload + 3 seed SAs | **YES — verbatim** |
| NetworkPolicies (16) | Reference only, kindnet doesn't enforce | **YES — verbatim** |
| ConfigMap + Secret | `apollo-airlines-config`, `apollo-airlines-secrets` | **YES — verbatim** |
| 4 StatefulSets (3 PG + redis) | PVCs Bound, init.sql via entrypoint hook | **YES — verbatim** |
| 6 app Deployments + frontend | All 2/2 ready | **YES** (Stage 4 adds probes + resources) |
| 3 seed Jobs | All succeeded | **YES — verbatim** |
| Code (`stages/stage3/code/`) | Snapshot of stage 2 | **YES — base for Stage 4 code changes** |

---

## Stage 4 (Flight Control) — what to build

> **Source: AGENTS.md §"Stage 4 (Flight Control)" + this section.** The
> AGENTS.md spec is correct but sparse. Read this section before starting.

**k8s manifest changes (the bulk of the work):**
1. **All 6 app Deployments** (`identity`, `flight`, `booking`, `search`,
   `notification`) get:
   - `livenessProbe` (HTTP, `/healthz` or `/healthz/live` — see code
     section below for the new endpoint layout)
   - `readinessProbe` (HTTP, `/healthz/ready` or `/readyz`)
   - `startupProbe` (HTTP, `/healthz/startup`) — gives slow-starting
     containers more time before liveness kicks in
   - `resources.requests` (cpu, memory) — minimum guarantee
   - `resources.limits` (cpu, memory) — hard cap; memory limit triggers
     OOMKill, CPU limit triggers throttling
2. **Frontend Deployment** (in `apollo-airlines-ui` ns) gets the same
   treatment. Note: frontend serves static NGINX so `/healthz` may need
   to be a custom endpoint or a simple `tcpSocket` probe on port 3000.
3. **PodDisruptionBudget (PDB)** for:
   - `frontend` (so a node drain doesn't take down the UI)
   - `booking` (the flagship service — keep at least 1 pod running
     during voluntary disruptions)
4. **StatefulSets (`identity-db`, `flight-db`, `booking-db`, `redis`):**
   - These already have `livenessProbe` + `readinessProbe` (`pg_isready` /
     `redis-cli ping`). They get `resources.requests` + `resources.limits`
     added — but **do NOT add a `startupProbe`**. Postgres initdb can
     take 5–10s on first start; a startupProbe is unnecessary because
     the init container blocks the main container until initdb is done.

**Code changes (see `stages/stage3/code/` for the current state):**
- Split the single `/healthz` endpoint into 3 distinct paths:
  - `/healthz/startup` — returns 200 once the app has finished
    bootstrapping (DB connected, schema verified, etc.)
  - `/healthz/live` — returns 200 if the process is alive (the kubelet
    restarts the pod on failure)
  - `/healthz/ready` — returns 200 only when DB + downstream
    dependencies are reachable
- Add graceful shutdown on SIGTERM:
  - HTTP server: stop accepting new connections, drain in-flight
    requests with a timeout, then exit
  - DB connection: close cleanly
  - Go: `signal.NotifyContext(ctx, syscall.SIGTERM)` + `srv.Shutdown(ctx)`
  - Python (identity): FastAPI's `lifespan` context manager + a signal
    handler that calls `app.shutdown()`
- Both Go and Python should log "received SIGTERM, shutting down" at
  the structured JSON logger so it's visible in `kubectl logs`

**Concrete endpoint mapping (recommendation):**
| Path | Purpose | k8s probe |
|---|---|---|
| `/healthz/startup` | App is fully bootstrapped | `startupProbe` |
| `/healthz/live` | Process is alive (cheap) | `livenessProbe` |
| `/healthz/ready` | All dependencies reachable | `readinessProbe` |

This means the AGENTS.md mention of `/readyz` (used in Stage 1–3) needs
to be reconsidered: either rename to `/healthz/ready` (consistent) or
keep `/readyz` as an alias. **Recommendation:** add the 3 new endpoints
and deprecate the old `/healthz` + `/readyz` paths (return 200 from
them for backward compat, but the new probes target the new paths).

---

## Critical insights from Stage 2 + Stage 3 sessions

These bit us during build. Re-read before touching the cluster.

### 1. Envoy Gateway v1.2.4 specifics
- The bundled `install.yaml` is **1.5MB** — must use `kubectl apply --server-side`
  (client-side apply would exceed the 256KB last-applied-config annotation limit)
- The `install.yaml` does **NOT** create a `GatewayClass` resource. You must
  create it manually:
  ```yaml
  apiVersion: gateway.networking.k8s.io/v1
  kind: GatewayClass
  metadata:
    name: eg
  spec:
    controllerName: gateway.envoyproxy.io/gatewayclass-controller
  ```
- `spec.infrastructure.serviceOverride` is a v1.3+ feature, NOT in v1.2.4
- The auto-created Envoy Service is `type: LoadBalancer` by default — MetalLB
  assigns an IP from `172.18.0.50–100` (set 4 pattern)
- Cross-namespace HTTPRoute attachments need:
  1. Explicit `parentRef.namespace: <gateway-ns>` in the HTTPRoute
  2. A `ReferenceGrant` in the target namespace allowing cross-namespace refs

### 2. MetalLB specifics
- v0.14.5 native speaker mode
- L2 mode (ARP/NDP) works without router config
- The bundled `metallb-native.yaml` is ~1900 lines — use `kubectl apply --server-side`
- Must use `--force-conflicts` because the webhook manages its own CA bundle
- The IP pool range must NOT overlap with kind node IPs
- Default pool `172.18.0.50–100` works on default kind docker network
- After apply, the webhook isn't ready immediately — wait for the controller
  pod to be 1/1 before creating IPAddressPool

### 3. kindnet does NOT enforce NetworkPolicies
- The `k8s/networkpolicies/` manifests are reference only
- `apply.sh` does NOT apply them (they're no-ops without a real policy-aware CNI)
- Stage 8 will tighten this with OPA Gatekeeper

### 4. Postgres init container DEADLOCK (fixed in Stage 3)
- Don't use a separate `initContainers[]` entry that runs `psql` against
  `127.0.0.1` after `pg_isready` — it deadlocks. The kubelet gates the
  main container on the init container's success, so init waits for main,
  main waits for init.
- **Correct pattern:** mount the init SQL ConfigMap at
  `/docker-entrypoint-initdb.d/` and set `PGDATA=/var/lib/postgresql/data/pgdata`.
  The official Postgres entrypoint runs the SQL during `initdb` on first
  start (empty PVC) and skips it on every subsequent restart.
- See `stages/stage3/README.md` §"Init Container pattern for schema" for
  the full discussion.

### 5. SQL gotchas with psql 15.18
- `TIME f.dep_time` (without explicit cast) fails with
  "syntax error at or near f". Use `f.dep_time::time` and cast the
  literal in the VALUES clause: `'08:00:00'::time`.
- The `flights` table needs `UNIQUE (flight_number, departure_time)`,
  not `flight_number UNIQUE` — the same flight flies daily, so the
  composite key lets the seed insert 31 rows per flight number.

### 6. nslookup is NOT in `python:3.12-slim`
- The identity service's image doesn't have `nslookup` or `dig`.
- Use `getent hosts <name>` in verify scripts (works in any minimal image).
- The `kubectl exec ... nslookup` pattern from Stage 1 won't work for
  identity in Stage 3+.

### 7. Teardown order matters (hanging webhooks)
- Deleting `envoy-gateway-install.yaml` while app namespaces are still
  around causes the apiservice deletion to hang on webhooks that
  reference services in the deleted namespace.
- **Correct order:** app namespaces first → Gateway/HTTPRoutes →
  Envoy Gateway (with `timeout 60` + `--force --grace-period=0` fallback)
  → MetalLB.
- See `stages/stage3/scripts/teardown.sh` for the working pattern.

### 8. Service patching rules
- Set 1 services have `type: NodePort + nodePort: 30xxx`
- Stage 3 (and all later stages) services are `type: ClusterIP`
- kubectl rejects apply if `nodePort` is set with `type: ClusterIP`

### 9. Service type confusion in init scripts
- App pods connect to the **regular** `identity-db` Service (not the
  headless). The headless service (`identity-db-headless`) is only used
  by the StatefulSet controller for pod-to-pod DNS.
- Don't change the app's `DATABASE_URL` when moving to StatefulSets.

---

## File layout (current — Stages 1-3)

```
stages/
├── stage1/                 # ✅ All 10 components as Deployments + Jobs
├── stage2/                 # ✅ 4 manifest sets (NodePort, Traefik, Envoy, Envoy+MetalLB)
│   ├── set1-baseline/      # 25/25
│   ├── set2-ingress/       # 25/25
│   ├── set3-gateway-nodeport/    # 26/26
│   └── set4-metallb-gateway/     # 28/28 — this is the persisted baseline
├── stage3/                 # ✅ 4 StatefulSets + PVCs, 53/53
│   ├── code/                    # snapshot of stage2/code
│   ├── k8s/                     # 4 sts + 6 deps + 3 jobs + gateway + metallb + ...
│   ├── scripts/                 # apply.sh, teardown.sh, verify.sh, build-images.sh
│   └── README.md                # concepts, apply/teardown, lessons learned
├── stage4/                 # ⚠️ PENDING — Probes, resource limits, QoS, PDB
├── stage5/                 # ⚠️ Helm charts + Kustomize + GitHub Actions
├── stage6/                 # ⚠️ Prometheus + Grafana + OpenTelemetry
├── stage7/                 # ⚠️ HPA, VPA, Redis cache, affinity/taints
├── stage8/                 # ⚠️ RBAC, SecurityContext, OPA, Vault
├── stage9/                 # ⚠️ EKS/GKE via Terraform
├── stage10/                # ⚠️ Linkerd, Argo Rollouts, Chaos Mesh
└── stage11/                # ⚠️ CRD operator, k3s, KEDA
```

---

## Cross-cutting decisions (carry forward)

| Decision | Value | Source |
|---|---|---|
| Traefik version | v3.1 (set 2 only) | User |
| Envoy Gateway version | v1.2.4 | User |
| MetalLB version | v0.14.5 native | User |
| GatewayClass name | `eg` | Envoy default |
| Hostnames | `<svc>.apollo.local` | User |
| Namespaces | `apps`, `ui` (2 not 3) | User (Stage 2) |
| Stage 3 base | Stage 2 set 4 (Envoy + MetalLB) — single set, no alternates | User (Stage 3) |
| TLS in Stage 3 | None | User |
| Frontend code changes (Stage 3) | None | User |
| Teardown behavior | Tear down EVERYTHING | User (Stage 2) |
| NetworkPolicy auto-apply | No (kindnet doesn't enforce) | Agreed (Stage 2) |
| /etc/hosts automation | Print only, no auto-modify | User |
| Image rebuild | Per-stage build-images.sh | User |
| Service account | Same name across all stages | Established (Stage 2) |
| Storage class | kind default (`local-path` / `standard`), no `storageClassName` in PVC | User (Stage 3) |
| Redis conversion to StatefulSet | Stage 3 (not Stage 7) | User override (Stage 3) |
| Schema bootstrap | Postgres entrypoint hook, not init container | Agreed (Stage 3 — see §4) |
| Seed pattern | One Job per DB, idempotent | User (Stage 3) |

---

## What's next (Stage 4: Flight Control)

The next stage teaches **reliable restarts** and **resource governance**:

- `livenessProbe`, `readinessProbe`, `startupProbe` for all 6 app
  Deployments and the frontend
- `resources.requests` and `resources.limits` for all 10 workloads
- `PodDisruptionBudget` for `frontend` and `booking`
- App code: split `/healthz` into `/healthz/{startup,live,ready}` and
  add graceful shutdown on SIGTERM
- The 4 StatefulSets (DBs + redis) already have probes — just add
  `resources.requests` and `resources.limits`
- Verify target: ~60 checks (53 from Stage 3 + new probe/resource/PDB
  assertions)

Build approach (recommended):
1. Copy `stages/stage3/` to `stages/stage4/` and `stages/stage3/code/` to
   `stages/stage4/code/`
2. Edit each app Deployment in `k8s/apps/<svc>/<svc>-dep.yaml` to add
   the 3 probes + 2 resources blocks
3. Add `k8s/pdb/` (new directory) with 2 PDBs: `frontend-pdb.yaml`,
   `booking-pdb.yaml`
4. Edit each DB StatefulSet + redis sts to add `resources.requests` and
   `resources.limits` (no probe changes)
5. Edit each app's main code to add the 3 new endpoints + signal handler
6. Add new verify.sh checks (probe config exists, resource config
   exists, PDB exists, `kubectl describe pod` shows the probes are
   active, deleting a pod triggers graceful-shutdown log lines)
7. Test on a fresh kind cluster: `apply.sh` → `verify.sh` →
   `teardown.sh`

---

## Stage 4 Status: COMPLETE (end-to-end tested on a fresh kind cluster)

| Metric | Result |
|---|---|
| `apply.sh` | exit 0, all 10 steps green |
| `verify.sh` | **129/129** checks pass (76 Stage 3 baseline + 53 new Stage 4 checks) |
| `teardown.sh` | exit 0, all 4 namespaces + 2 controllers gone |
| Graceful shutdown demo | "Received SIGTERM, shutting down gracefully" log line captured on booking pod delete |
| Frontend restart demo | New pod serves /healthz/ready=ready within ~5s of delete |
| Last tested on | fresh kind cluster, kind v0.31.0, k8s v1.36.0 |

**Stage 4 changes vs Stage 3:**

- All 6 app Deployments got 3 distinct probes (startup/live/ready),
  `resources.requests == limits` (Guaranteed QoS), and
  `terminationGracePeriodSeconds: 30`.
- All 4 StatefulSets got `resources.requests == limits` and
  `terminationGracePeriodSeconds: 60` (no probe changes).
- New `k8s/pdb/` directory: `booking-pdb.yaml` (apps ns) + `frontend-pdb.yaml`
  (ui ns), both `minAvailable: 1`.
- Go services (flight/booking/search/notification): 3 new probe handlers +
  `http.Server.Shutdown` graceful drain + SIGTERM handler that logs
  "Received SIGTERM, shutting down gracefully".
- Python/identity: 3 new probe handlers + `signal.SIGTERM` handler that
  logs + `uvicorn.run(..., timeout_graceful_shutdown=30)`.
- Frontend: new `nginx.conf` adds three `location = /healthz/*` blocks
  returning 200 unconditionally. `Dockerfile` now `COPY nginx.conf` instead
  of inlining the config.
- Verify target: 129 checks. `apply.sh` applies `k8s/pdb/` at step 4
  (after apps, before statefulset waits). `teardown.sh` is reused
  verbatim from Stage 3.

---

## Stage 4 → Stage 5 baseline (what carries over)

The next agent starts from `stages/stage4/` and produces `stages/stage5/`.
Stage 4's `apply.sh` is the runnable baseline. **Don't rebuild from
scratch** — copy `stages/stage4/` and add Stage 5's changes.

| Layer | Stage 4 state | Carries to Stage 5? |
|---|---|---|
| Access stack (Envoy Gateway + MetalLB) | Gateway Programmed, IP `172.18.0.50`, 6 HTTPRoutes | **YES — verbatim, no changes** |
| ServiceAccounts (13) | 1 per workload + 3 seed SAs | **YES — verbatim** |
| NetworkPolicies (16) | Reference only, kindnet doesn't enforce | **YES — verbatim** |
| ConfigMap + Secret | `apollo-airlines-config`, `apollo-airlines-secrets` | **YES — verbatim** |
| 4 StatefulSets (3 PG + redis) | PVCs Bound, Guaranteed QoS, 60s grace | **YES — verbatim** |
| 6 app Deployments + frontend | All 2/2 ready, 3 probes + Guaranteed QoS + 30s grace | **YES** (Stage 5 makes them Helm-templated) |
| 2 PodDisruptionBudgets (booking + frontend) | `minAvailable=1`, status populated | **YES — verbatim** |
| 3 seed Jobs | All succeeded | **YES — verbatim** |
| Code (`stages/stage4/code/`) | 3 probe endpoints + SIGTERM drain in all 5 backends + 1 frontend NGINX config | **YES — base for Stage 5 code changes (likely none)** |

---

## Stage 4 (Flight Control) — what was built (reference for Stage 5 agent)

> The Stage 4 spec was in AGENTS.md §"Stage 4 (Flight Control)" + the
> section above. This is a recap of the *actual* implementation, in case
> the next agent needs to know exact field names and conventions.

**k8s manifest changes (the bulk of the work):**
1. **All 6 app Deployments** (`identity`, `flight`, `booking`,
   `search`, `notification`) get:
   - `startupProbe` → `/healthz/startup` (initialDelay 0, period 5s, failureThreshold 6)
   - `livenessProbe` → `/healthz/live` (initialDelay 15, period 10s, failureThreshold 3)
   - `readinessProbe` → `/healthz/ready` (initialDelay 5, period 5s, failureThreshold 3)
   - `resources.requests == limits`:
     - app default: `cpu: 100m, memory: 128Mi` (identity, flight, search)
     - flagship: `cpu: 200m, memory: 256Mi` (booking)
     - low: `cpu: 50m, memory: 64Mi` (notification, frontend)
   - `terminationGracePeriodSeconds: 30`
2. **Frontend Deployment** (in `apollo-airlines-ui` ns) gets the same
   3 probes + `cpu: 50m, memory: 64Mi` + `terminationGracePeriodSeconds: 30`.
3. **PodDisruptionBudget (PDB)** for:
   - `frontend` (`apollo-airlines-ui` ns, `minAvailable: 1`)
   - `booking` (`apollo-airlines-apps` ns, `minAvailable: 1`)
4. **StatefulSets** (`identity-db`, `flight-db`, `booking-db`, `redis`):
   - Already have `livenessProbe` + `readinessProbe` (`pg_isready` / `redis-cli ping`)
   - Got `resources.requests == limits`: PG `200m/256Mi`, redis `100m/128Mi`
   - Got `terminationGracePeriodSeconds: 60`
   - **Did NOT** get `startupProbe` — Postgres' `initdb` is the implicit
     start; adding a `startupProbe` would race with the entrypoint.

**Code changes:**

The 3 distinct probe paths are:
- `/healthz/startup` — 200 once the HTTP server is up
- `/healthz/live` — 200 unconditionally (process is alive)
- `/healthz/ready` — 200 if dependency reachable, 503 otherwise

Legacy `/healthz` and `/readyz` are kept returning 200 for back-compat
(stage 1–3 smoke tests, external monitoring).

Graceful shutdown:
- Go: `http.Server{Addr:":"+port, Handler: r}` + `go srv.ListenAndServe()`,
  then `signal.Notify(quit, syscall.SIGTERM)` → log "Received SIGTERM,
  shutting down gracefully" → `srv.Shutdown(ctx)` with 30s timeout →
  `db.Close()`.
- Python (identity): register a *prior* SIGTERM handler that just logs,
  then `uvicorn.run(..., timeout_graceful_shutdown=30)`. uvicorn's built-in
  handler does the actual drain.
- Frontend (NGINX): exits within ~1s of SIGTERM. No app-level drain.

---

## Critical insights from Stage 4 (read before changing)

1. **`kubectl logs <old-pod> --previous` returns NotFound once the pod
   is removed from the API server.** The graceful-shutdown verify uses
   `kubectl logs --follow` in a background process *before* the delete,
   then greps the captured output. See
   `stages/stage4/scripts/verify.sh` for the working pattern.

2. **uvicorn's default SIGTERM handler is the right one — don't replace
   it.** `sys.exit(0)` on SIGTERM drops in-flight requests. Register a
   *prior* handler that just logs and let uvicorn do the drain.

3. **DB StatefulSets don't need a `startupProbe`.** Postgres' own
   `initdb` blocks the main process from accepting connections, so
   `pg_isready` is an implicit startup check. A `startupProbe` would
   race with the entrypoint.

4. **NGINX reports Ready before it serves HTTP in some cases.** The
   frontend verify retries 30× and re-fetches the pod name each
   iteration (the API server returns the old deleting pod for 1-2s
   after `kubectl delete --wait=false`).

5. **The teardown script from Stage 3 handles the Gateway/MetalLB
   ordering correctly. Reused verbatim.** The teardown order is:
   app namespaces → Gateway + HTTPRoutes → Envoy (with `timeout 60`
   + `--force --grace-period=0` fallback) → MetalLB.

6. **Service patching rules** (from Stage 2 carryover):
   - Sets 2/3/4 services are `type: ClusterIP` (NodePort removed)
   - kubectl rejects apply if `nodePort` is set with `type: ClusterIP`

7. **Service type confusion in init scripts**: App pods connect to the
   **regular** `identity-db` Service (not the headless). The headless
   service (`identity-db-headless`) is only used by the StatefulSet
   controller for pod-to-pod DNS. Don't change the app's `DATABASE_URL`
   when moving to StatefulSets.

8. **Image rebuild**: each stage's `apply.sh` calls `build-images.sh`
   which builds from `${CODE_DIR}` (i.e., `stages/stage4/code/`).
   When copying to stage5, the build step rebuilds the stage5 code
   into a `apollo11/<svc>:latest` image and `kind load`s it.

---

## Cross-cutting decisions (carry forward)

| Decision | Value | Source |
|---|---|---|
| Traefik version | v3.1 (set 2 only — not used in stage 3+) | User |
| Envoy Gateway version | v1.2.4 | User |
| MetalLB version | v0.14.5 native | User |
| GatewayClass name | `eg` | Envoy default |
| Hostnames | `<svc>.apollo.local` | User |
| Namespaces | `apps`, `ui` (2 not 3) | User (Stage 2) |
| Stage 3 base | Stage 2 set 4 (Envoy + MetalLB) | User (Stage 3) |
| Stage 4 base | Stage 3 (StatefulSets + access stack) | User (Stage 4) |
| TLS in Stages 3+ | None | User |
| Frontend code changes (Stage 4) | NGINX config adds probe locations | Agreed (Stage 4) |
| Teardown behavior | Tear down EVERYTHING | User (Stage 2) |
| NetworkPolicy auto-apply | No (kindnet doesn't enforce) | Agreed (Stage 2) |
| /etc/hosts automation | Print only, no auto-modify | User |
| Image rebuild | Per-stage build-images.sh | User |
| Service account | Same name across all stages | Established (Stage 2) |
| Storage class | kind default (`local-path` / `standard`), no `storageClassName` in PVC | User (Stage 3) |
| Redis conversion to StatefulSet | Stage 3 (not Stage 7) | User override (Stage 3) |
| Schema bootstrap | Postgres entrypoint hook, not init container | Agreed (Stage 3) |
| Seed pattern | One Job per DB, idempotent | User (Stage 3) |
| QoS class | Guaranteed (requests == limits) on all 10 pods | User (Stage 4) |
| Resource tiers | app: 100m/128Mi, booking: 200m/256Mi, low: 50m/64Mi, PG: 200m/256Mi, redis: 100m/128Mi | Agreed (Stage 4) |
| terminationGracePeriodSeconds | 30s apps, 60s DBs | Agreed (Stage 4) |
| PDB scope | booking + frontend only, `minAvailable: 1` | Agreed (Stage 4) |

---

## What's next (Stage 5: Payload Integration)

The next stage teaches **packaging**:
- Convert the 27 raw manifests into a **Helm chart** with `values.yaml`
  and `templates/` (one template per kind)
- Add **Kustomize overlays** for `dev/`, `staging/`, `prod/`
- Add a **GitHub Actions** workflow that runs lint + `kubectl apply --dry-run`

No code changes are expected for Stage 5 — the Go services, Python service,
and NGINX frontend all stay the same. The work is purely in the
manifest + CI layer.

Build approach (recommended):
1. Copy `stages/stage4/` to `stages/stage5/`
2. Create `stages/stage5/helm/apollo-airlines/` with `Chart.yaml`,
   `values.yaml`, `templates/`
3. Create `stages/stage5/overlays/{dev,staging,prod}/` with `kustomization.yaml`
4. Create `.github/workflows/deploy.yml` (or place it under
   `stages/stage5/.github/workflows/`)
5. Test on a fresh kind cluster: render the Helm chart, apply, verify
   129/129 still pass, then teardown

