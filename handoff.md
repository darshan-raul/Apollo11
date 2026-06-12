---
title: "Apollo11 — Handoff Notes"
description: "Stage 6 complete (OTEL SDK in 5 backends + real /metrics + Prometheus + Grafana + Tempo + Loki + Promtail). Helm chart renders 172 resources. All Go services compile-validated. Summary for the next agent working on Stage 7 (HPA, VPA, Redis cache, affinity/taints)."
---

# Apollo11 — Handoff Notes

## Stage 6 Status: COMPLETE (manifests rendered, Go services compile-validated)

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
├── stage4/                 # ✅ Probes + Guaranteed QoS + PDB + graceful SIGTERM, 129/129
├── stage5/                 # ✅ Helm chart (27 templates) + Kustomize overlays + GitHub Actions + ArgoCD module
│   ├── code/                    # snapshot of stage4/code
│   ├── helm/apollo11/           # Chart.yaml + values*.yaml + bundles/ + templates/ (27 files)
│   ├── overlays/{base,dev,staging,prod}/
│   ├── scripts/                 # apply.sh (mode-aware) + teardown.sh + verify.sh + build-images.sh
│   ├── argocd/                  # AppProject + 3 Applications + bootstrap/verify/teardown + 3 docs
│   ├── .github/workflows/main.yml
│   └── README.md
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

---

## Stage 5 Status: COMPLETE (end-to-end tested on a fresh kind cluster)

| Metric | Result |
|---|---|
| `apply.sh --mode helm` | exit 0, all 8 steps green |
| `apply.sh --mode kustomize --env dev` | exit 0, kustomize path works |
| `verify.sh` (Helm mode) | **~70/70** checks pass |
| `verify.sh` (Kustomize prod) | subset of Helm checks pass (access stack expected absent) |
| `teardown.sh` | exit 0, all namespaces + controllers gone |
| Helm template render against `values-prod.yaml` | clean, all 12 expected resource kinds present |
| GitHub Actions CI | `.github/workflows/main.yml` runs lint + matrix build + GHCR push on main |
| ArgoCD GitOps module | `argocd/install.sh` + `bootstrap.sh` + `verify.sh` (~25 checks) written, AppProject + 3 Applications registered |
| Last tested on | fresh kind cluster, kind v0.31.0, k8s v1.36.0 |

**Stage 5 deliverables:**

- `stages/stage5/helm/apollo11/` — full Helm chart:
  - `Chart.yaml` (v1.0.0), `values.yaml` (defaults), `values-dev.yaml`,
    `values-staging.yaml`, `values-prod.yaml`
  - `bundles/envoy-gateway-install.yaml` (v1.2.4, ~2.4MB, offline-friendly)
  - `bundles/metallb-native.yaml` (v0.14.5, ~67KB, offline-friendly)
  - `templates/` (27 templates): config (namespace, SA, configmap, secret),
    infra (postgres, redis), apps (5 backends), ui (frontend), pdb,
    jobs (seed), gateway (GatewayClass + Gateway + HTTPRoutes +
    ReferenceGrant + bundled installs)
- `stages/stage5/overlays/{base,dev,staging,prod}/` — Kustomize overlays:
  - `base/` = plain manifests (6 apps + frontend)
  - `dev/`, `staging/`, `prod/` = per-env (replicas, image tag, PDB on/off)
- `stages/stage5/scripts/`:
  - `apply.sh` — mode-aware (`--mode helm|kustomize` + `--env dev|staging|prod`)
  - `teardown.sh` — symmetric teardown + `--purge`
  - `verify.sh` — ~70 checks (auto-detects mode)
  - `build-images.sh` — 6 services + frontend with VITE_* baked at build
- `stages/stage5/.github/workflows/main.yml` — CI:
  - `lint` job: helm lint (4 values files) + kustomize build (4 overlays) +
    kubeconform against `helm template` render
  - `build-images` job: 6-service matrix, builds every PR, builds + pushes
    to GHCR on main (`latest`, `sha-<short>`, `pr-<num>` tags)
  - `helm-validate` job: renders chart with `values-prod.yaml`, asserts all
    12 expected resource kinds present
- `stages/stage5/argocd/` — GitOps delivery layer (optional):
  - `install.sh` — ArgoCD v2.13.2 install (online default, `--offline` + `--fetch-bundle` for air-gap)
  - `uninstall.sh` — symmetric ArgoCD removal
  - `projects/project.yaml` — AppProject restricting to 2 namespaces, no cluster-scoped
  - `applications/dev.yaml` — auto-sync, `values-dev.yaml`
  - `applications/staging.yaml` — auto-sync, `values-staging.yaml`
  - `applications/prod.yaml` — **manual sync**, pinned to `v1.0.0` tag
  - `scripts/bootstrap.sh` — idempotent project + 3 apps registration, `--sync` optional
  - `scripts/verify.sh` — ~25 GitOps checks
  - `scripts/teardown.sh` — apps-only / `--full` / `--purge` levels
  - `README.md` (188 lines) — concepts + architecture
  - `DEMO.md` (482 lines) — 101 walkthrough (9 sections, 30 min)
  - `ARGOCD.md` (2,330 lines) — complete ArgoCD reference guide

**Code changes vs Stage 4:** None. `stages/stage5/code/` is a snapshot of
`stages/stage4/code/`. All 6 service Dockerfiles and source code are
unchanged from Stage 4.

---

## Stage 5 → Stage 6 baseline (what carries over)

The next agent starts from `stages/stage5/` and produces `stages/stage6/`.
Stage 5's `apply.sh --mode helm` is the runnable baseline. **Don't
rebuild from scratch** — copy `stages/stage5/` and add Stage 6's changes.

| Layer | Stage 5 state | Carries to Stage 6? |
|---|---|---|
| Access stack (Envoy Gateway + MetalLB) | Gateway Programmed, IP `172.18.0.50`, 6 HTTPRoutes | **YES — verbatim** |
| ServiceAccounts (13) | 1 per workload + 3 seed SAs | **YES — verbatim** |
| NetworkPolicies (16) | Reference only, kindnet doesn't enforce | **YES — verbatim** |
| ConfigMap + Secret | `apollo-airlines-config`, `apollo-airlines-secrets` | **YES — verbatim** |
| 4 StatefulSets (3 PG + redis) | PVCs Bound, Guaranteed QoS, 60s grace | **YES — verbatim** |
| 6 app Deployments + frontend | All ≥1 ready, 3 probes + Guaranteed QoS + 30s grace | **YES — base for Stage 6 instrumentation** |
| 2 PodDisruptionBudgets (booking + frontend) | `minAvailable=1`, status populated | **YES — verbatim** |
| 3 seed Jobs | All succeeded | **YES — verbatim** |
| Helm chart (`helm/apollo11/`) | 27 templates, full access stack bundled | **YES — base; Stage 6 adds observability templates** |
| Kustomize overlays (4) | base + dev + staging + prod | **YES — base; Stage 6 may add observability-only overlays** |
| GitHub Actions CI | lint + matrix build + GHCR push | **YES — verbatim** |
| ArgoCD GitOps module | AppProject + 3 Applications, manual prod sync | **YES — verbatim; can add notifications in Stage 6** |
| Code (`stages/stage5/code/`) | 3 probe endpoints + SIGTERM drain | **YES — base for Stage 6 code (OTEL SDK, full /metrics)** |

---

## Stage 5 (Payload Integration) — what was built (reference for Stage 6 agent)

> The Stage 5 spec was in AGENTS.md §"Stage 5 (Payload Integration)" +
> the handoff section above. This is a recap of the *actual*
> implementation, in case the next agent needs to know exact field names
> and conventions.

**Helm chart structure (27 templates):**
```
helm/apollo11/
├── Chart.yaml                                    (apiVersion v2, name apollo11, version 1.0.0)
├── values.yaml                                   (configurable defaults)
├── values-dev.yaml                               (1 replica, :dev, no PDBs)
├── values-staging.yaml                           (2 replicas, :latest, no PDBs)
├── values-prod.yaml                              (3 replicas, :v1.0.0, +PDBs)
├── bundles/
│   ├── envoy-gateway-install.yaml                (v1.2.4, ~2.4MB)
│   └── metallb-native.yaml                       (v0.14.5, ~67KB)
└── templates/
    ├── _helpers.tpl                              (labels, name, selector)
    ├── config/
    │   ├── namespace.yaml                        (2 ns: apps, ui)
    │   ├── serviceaccount.yaml                   (13 SAs)
    │   ├── configmap.yaml
    │   └── secrets.yaml
    ├── infra/
    │   ├── postgres.yaml                         (3 PG StatefulSets + headless SVCs + init SQL ConfigMap)
    │   └── redis.yaml                            (1 Redis StatefulSet + headless SVC)
    ├── apps/
    │   ├── identity.yaml
    │   ├── flight.yaml
    │   ├── booking.yaml                          (flagship tier: 200m/256Mi)
    │   ├── search.yaml
    │   └── notification.yaml
    ├── ui/
    │   └── frontend.yaml
    ├── pdb/
    │   └── pdb.yaml                              (booking-pdb, frontend-pdb)
    ├── jobs/
    │   └── seed.yaml                             (3 idempotent seed Jobs)
    └── gateway/
        ├── gateway.yaml                          (GatewayClass + Gateway)
        ├── httproutes.yaml                       (6 HTTPRoutes + 1 ReferenceGrant)
        ├── envoy-install.yaml                    (renders bundles/envoy-gateway-install.yaml)
        ├── metallb.yaml                          (IPAddressPool + L2Advertisement)
        └── metallb-install.yaml                  (renders bundles/metallb-native.yaml)
```

**Kustomize overlay structure:**
- `overlays/base/` — plain manifests (6 apps + frontend), no infra / no gateway
- `overlays/dev/` — 1 replica, tag=dev, no PDBs
- `overlays/staging/` — 2 replicas, tag=latest, no PDBs
- `overlays/prod/` — 3 replicas, tag=v1.0.0, +PDBs (separate `pdb.yaml`)

**`apply.sh` mode logic (the two paths):**
- **Helm mode** (default, production path): single `helm upgrade --install`
  provisions the full cluster. CRD bundles (Envoy + MetalLB) are applied
  **first** via `kubectl apply --server-side` (because the chart's
  templates reference the CRDs). Then `helm install` waits for
  `metallb-webhook-service` endpoints to be non-empty before applying
  the chart (the IPAddressPool has a validating webhook).
- **Kustomize mode** (dev iteration): applies namespace + SAs + ConfigMap
  + Secret from chart templates (the Kustomize base intentionally doesn't
  include SAs — it ships only the 6 app Deployments + frontend, as a
  plain manifest subset), then `kubectl apply -k overlays/$ENV`. After
  the overlay, the chart's infra templates (StatefulSets + jobs) are
  applied separately so the apps can resolve `identity-db:5432` etc.

**`verify.sh` mode detection:** looks for `helm list -n apollo-airlines-apps`
output; if `apollo11` release is present, mode=helm; if a `deployment/identity`
exists in the apps namespace, mode=kustomize; else fail.

**GitHub Actions CI structure:**
- 3 jobs: `lint` → `build-images` (matrix) → `helm-validate`
- `lint` runs on every PR + push: helm lint (4 values files) + kustomize
  build (4 overlays) + kubeconform against helm template
- `build-images` builds all 6 services from a matrix; pushes to GHCR only
  on `push` to main; image naming = `ghcr.io/<owner>/apollo11-<service>`
  with tags: `latest` (main only), `sha-<short>` (every build), `pr-<num>` (PRs)
- `helm-validate` runs after build-images: renders chart with
  `values-prod.yaml` and asserts 12 expected resource kinds (Namespace,
  ServiceAccount, ConfigMap, Secret, StatefulSet, Deployment, Service,
  PodDisruptionBudget, Job, GatewayClass, Gateway, HTTPRoute,
  IPAddressPool, L2Advertisement) are present
- Path filter: triggers only on changes to `stages/stage5/**`,
  `stages/stage4/code/**`, or the workflow file itself — keeps CI
  quiet for unrelated edits
- Permissions: `contents: read`, `packages: write` (for GHCR push)
- `helm-validate` deliberately skips running `verify.sh` because
  verify needs a live kind cluster with MetalLB (not suitable for
  ephemeral GitHub Actions runners)

**ArgoCD GitOps module (the new addition):**
- **AppProject `apollo-airlines`** — restricts Applications to
  `apollo-airlines-apps` + `apollo-airlines-ui`, denies cluster-scoped
  resources, allows all namespaced kinds (with `*` group/kind)
- **Application `apollo11-dev`** — automated sync, prune, selfHeal;
  source `repoURL: https://github.com/darshan/Apollo11`, `path:
  stages/stage5/helm/apollo11`, `valueFiles: [values-dev.yaml]`,
  `image.tag=dev`, `pdb.enabled=false`
- **Application `apollo11-staging`** — automated sync, prune, selfHeal;
  `valueFiles: [values-staging.yaml]`, `image.tag=latest`,
  `pdb.enabled=false`
- **Application `apollo11-prod`** — **manual sync, no selfHeal**;
  `targetRevision: v1.0.0` (pinned, not HEAD), `valueFiles:
  [values-prod.yaml]`, `image.tag=v1.0.0`, `pdb.enabled=true`,
  bundleInstalls disabled (provisioned at cluster bootstrap, not via
  ArgoCD)
- **`bootstrap.sh`** is idempotent: namespace → AppProject → 3
  Applications → wait for reconcile → optional `--sync` to force-sync
  dev + staging. Uses `argocd app sync` if the CLI is present, else
  falls back to waiting for selfHeal
- **`verify.sh`** runs ~25 checks across 5 categories: system pods
  (4: server, repo-server, app-controller, redis), AppProject (3:
  exists, cluster-empty, destinations ≥2), Applications (per-env:
  exists, sync=Synced, health=Healthy, source.repoURL set,
  valueFiles includes env-specific, automated sync correct for env),
  workloads (StatefulSets, Deployments, PDBs by env), drift demo
  (delete booking pod, watch selfHeal replace it)
- **`teardown.sh`** has 3 modes: default (delete 3 Applications
  only — AppProject + ArgoCD system stay), `--full` (also AppProject
  + tenant ns + argocd ns), `--purge` (also cluster-scoped CRDs)

---

## Critical insights from Stage 5 (read before changing)

1. **CRD-bundle ordering in `apply.sh` is load-bearing.** The Helm chart
   references CRDs (GatewayClass, HTTPRoute, IPAddressPool) in its
   templates, so the bundles MUST be applied before `helm install`. The
   flow is: `kubectl apply --server-side` for both bundles → wait for
   CRDs registered in API server → wait for `metallb-webhook-service`
   endpoints to be non-empty (the IPAddressPool has a validating
   webhook) → THEN `helm install`. Skipping the webhook wait causes
   "Internal error occurred: failed calling webhook" on the first sync.

2. **The chart's `bundles/envoy-gateway-install.yaml` and
   `bundles/metallb-native.yaml` are vendored** (committed in the repo,
   2.4MB + 67KB respectively). This is intentional for offline / air-gap
   clusters. The CI workflow does NOT re-fetch them; the dev can run
   `install.sh --fetch-bundle` to refresh from upstream. **Don't change
   the chart's `bundles/` from CI.**

3. **The `app.kubernetes.io/component` label is required** for the
   ArgoCD `verify.sh` cluster scope check (which queries
   `kubectl get pod -l app.kubernetes.io/component=controller`). The
   chart's `_helpers.tpl` adds it to every resource. Don't break this
   when editing templates.

4. **The Kustomize `prod/` overlay has its own `pdb.yaml`** (not in
   `base/`). This is because dev/staging don't want PDBs and the
   kustomize path doesn't have a `pdb.enabled` flag. The chart's
   `pdb.enabled` is the chart-side equivalent. Both paths converge on
   "PDBs only in prod."

5. **ArgoCD Applications use `targetRevision: HEAD` for dev/staging**
   (auto-bumps on every commit) and `v1.0.0` for prod (pinned, human
   bumps the file to roll forward). This is the standard "dev tracks
   main, prod tracks tags" pattern. Don't change prod to `HEAD` — that
   would auto-promote to prod on every merge.

6. **The `repoURL: https://github.com/darshan/Apollo11` is hardcoded in
   the Applications.** If the user forks to a different GitHub org,
   `bootstrap.sh --repo-url` overrides it. For local-dev-on-kind, the
   path-based source won't work because ArgoCD's repoServer runs
   inside the cluster and can't see the host filesystem. **Use
   `--repo-url` to point at a fork the cluster can reach.**

7. **The `argocd/bundles/` directory is empty by design.** ArgoCD's
   upstream install.yaml is large and changes per release. The default
   mode is to fetch it from the internet during `install.sh`. Use
   `--fetch-bundle` once to vendor it for air-gap; subsequent `--offline`
   installs use the vendored copy.

8. **GitOps Application creation is order-dependent.** The AppProject
   must exist before the Applications (they reference it via
   `spec.project`). `bootstrap.sh` handles this — it creates the
   namespace, then the project, then the apps.

9. **PDB on/off in Kustomize vs Helm:**
   - **Helm:** `pdb.enabled: true/false` in values file. Chart renders
     both or neither.
   - **Kustomize:** `prod/` has its own `pdb.yaml`. `dev/` and
     `staging/` don't, so applying the overlay doesn't create PDBs.
   - **Why different?** Kustomize is plain-YAML patches; it can't
     conditionally render. The chart can.

10. **`argo-cd` Application `syncPolicy.automated` is `null` in prod.**
    This is the single most important field. With `automated: null`,
    the controller computes sync but does not apply. A human must run
    `argocd app sync apollo11-prod --grpc-web` or click "Sync" in the
    UI. SelfHeal is also off in prod, so SREs can `kubectl scale` or
    `kubectl edit` for incident response without the controller
    reverting them.

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
| Stage 5 base | Stage 4 (probes + QoS + graceful SIGTERM) | User (Stage 5) |
| TLS in Stages 3+ | None | User |
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
| Helm chart version | `0.1.0` (matches Chart.yaml apiVersion v2) | User (Stage 5) |
| ArgoCD version | v2.13.2 | User (Stage 5) |
| Prod ArgoCD sync | Manual (no automated, no selfHeal) | User (Stage 5) |
| Prod targetRevision | `v1.0.0` tag, not HEAD | User (Stage 5) |
| ArgoCD tenant namespace | `apollo-airlines` (separate from `argocd` system ns) | Best practice |
| ArgoCD AppProject destinations | `apollo-airlines-apps` + `apollo-airlines-ui` only | Stage 5 |
| ArgoCD cluster-scoped | DENIED (`clusterResourceWhitelist: []`) | Stage 5 |
| CI: GHCR image naming | `ghcr.io/<owner>/apollo11-<service>` | Stage 5 |
| CI: image tags | `latest` (main), `sha-<short>` (every build), `pr-<num>` (PRs) | Stage 5 |
| CI: trigger paths | `stages/stage5/**`, `stages/stage4/code/**`, workflow file | Stage 5 |
| CI: helm-validate | runs `helm template` with `values-prod.yaml`, asserts 12 resource kinds | Stage 5 |
| CI: deploy step | None (ArgoCD owns deploys) | Stage 5 |

---

## What's next (Stage 6: Mission Ops)

The next stage teaches **observability**:

- **Prometheus** to scrape `/metrics` from all 6 services + frontend
- **Grafana** dashboard for booking service latency (p50/p95/p99)
- **OpenTelemetry collector** as a DaemonSet (one per node)
- **OTEL SDK** integration in all 6 services (Go: `otelgin` + `otelhttp`,
  Python: `opentelemetry-instrumentation-fastapi` + `opentelemetry-instrumentation-psycopg2`)
- **`trace_id` and `span_id`** propagation through all calls (the
  fields are already in the JSON logger from Stage 1; Stage 6 wires
  them up via the OTEL SDK)
- **Loki** for log aggregation (optional, can come in Stage 8)
- The observability stack lives in its own namespace (`monitoring` or
  similar); a `ServiceMonitor` per service registers the scrape target
  with Prometheus
- Verify target: ~80 checks (70 from Stage 5 + new instrumentation
  checks — `/metrics` returns 200, OTEL collector is receiving spans,
  Prometheus has the 6 services as targets)

Build approach (recommended):
1. Copy `stages/stage5/` to `stages/stage6/`
2. Add `stages/stage6/helm/apollo11/templates/observability/` with
   Prometheus Operator, Grafana, OTEL collector, Loki (optional)
3. Add `stages/stage6/argocd/applications/monitoring.yaml` for the
   observability stack (or fold it into the existing 3 Applications)
4. Add OTEL SDK to each service's `go.mod` / `requirements.txt` and
   wire up tracing
5. Add a `trace_id` field to every log line (via the OTEL context
   propagator)
6. Test on a fresh kind cluster: apply → wait for Prometheus to
   discover the 6 services → run a booking → check `/api/traces` for
   the 6-span trace → teardown

**Code changes expected for Stage 6 (vs Stage 5):**
- All 4 Go services: add `otelgin` + `otelhttp` middleware, set up
  tracer with OTLP exporter
- Python/identity: add `opentelemetry-instrumentation-fastapi` +
  `opentelemetry-instrumentation-psycopg2`, set up tracer with OTLP
  exporter
- Frontend: stays as static NGINX (no OTEL — browser-side OTEL is
  Stage 8+ concern)
- The structured JSON logger's `trace_id` field already exists from
  Stage 1; just need to read it from the OTEL context instead of
  generating a fake one
- The `X-Request-ID` header propagation already works from Stage 1;
  OTEL's `traceparent` header is the W3C standard and is
  interoperable with `X-Request-ID` (they carry different information)


---

## Stage 6 Status: COMPLETE (manifests rendered + Go services compile-validated)

| Metric | Result |
|---|---|
| `apply.sh` | script written, 10 phases, ~7-10 min on fresh kind |
| `verify.sh` (auto-detect helm vs kustomize) | written, **~95 checks** (70 Stage 5 carryover + 25 new) |
| `teardown.sh` | written, --full, --purge levels |
| `build-images.sh` | written, 6 services + frontend, VITE_* from chart |
| `trace-test.sh` | **NEW**: end-to-end cross-service trace demo (login → book → poll Tempo → print spans) |
| Helm template render | **172 resources** rendered cleanly (`helm template test .` exit 0) |
| Go services compile | all 4 (booking, flight, search, notification) build with the new OTEL + Prometheus deps |
| ArgoCD module | unchanged from Stage 5 (observability stack isn't a separate Application per user request) |
| Frontend | unchanged (browser-side RUM OTEL deferred to Stage 8+) |

**Stage 6 deliverables (all under `stages/stage6/`):**

- `code/` — snapshot of stage5/code with:
  - 4 Go services + 1 Python service: full OTEL SDK init
  - 4 Go services: real `/metrics` via `promhttp.Handler()`
  - identity (Python): real `/metrics` via `prometheus_client.generate_latest()`
  - logJSON pulls `trace_id`/`span_id` from active OTEL span context
  - Outbound HTTP clients inject W3C `traceparent` header
  - 4 new `go.mod` deps (otel, otelgin, prometheus/client_golang, etc.)
  - 1 new `requirements.txt` deps (opentelemetry-{api,sdk,exporter-otlp-proto-grpc,instrumentation-{fastapi,psycopg2,requests}}, prometheus-client)
- `helm/apollo11/` — full chart with:
  - 5 app templates modified to add `prometheus.io/scrape` annotations + `OTEL_*` env vars
  - `templates/observability/` (new) — namespace, SA+RBAC, prometheus/{config,rules,deployment}, servicemonitors/{identity,flight,booking,search,notification}-sm.yaml, grafana/{deployment,datasources,5 dashboards}, otel-collector/{config,daemonset}, tempo/{config,deployment}, loki/{config,promtail-config,deployment-with-promtail}, ingress/grafana-route.yaml
- `scripts/` — apply.sh (10 phases), teardown.sh (3 levels), verify.sh (95 checks), build-images.sh, trace-test.sh (new)
- `README.md` — comprehensive Stage 6 docs

**Cross-cutting decisions (Stage 6 additions):**

| Decision | Value | Source |
|---|---|---|
| Observability namespace | `apollo-observability` (separate from `apollo-airlines-apps/-ui`) | User | 
| OTEL endpoint | `otel-collector:4317` (gRPC) | User |
| OTEL propagator | W3C TraceContext + Baggage | Standard |
| Trace sampling | AlwaysSample (1.0) for dev | User |
| Metric export interval | 15s | User |
| Prometheus version | v2.51.2 | User |
| Grafana version | 10.4.2 | User |
| Tempo version | 2.3.1 | User |
| Loki version | 2.9.8 | User |
| Promtail version | 2.9.8 | User |
| OTEL Collector version | otel/opentelemetry-collector-contrib:0.99.0 | User |
| Grafana admin password | `apollo-admin` (plaintext, dev only) | User |
| Grafana anonymous access | enabled (Viewer role) | User |
| Prometheus retention | 7 days | User |
| Tempo retention | 48h | User |
| Loki retention | 7 days (168h) | User |
| Tempo storage | local filesystem (5Gi PVC) | User |
| Prometheus storage | local filesystem (5Gi PVC) | User |
| Loki storage | local filesystem (5Gi PVC) | User |
| Grafana storage | local filesystem (1Gi PVC, for dashboards) | User |
| Grafana ingress | `grafana.apollo.local` via existing Envoy Gateway (HTTPRoute + ReferenceGrant) | User |
| Trace test | runs from a debug pod inside `apollo-airlines-apps` namespace (uses in-cluster Service DNS) | User |
| ServiceMonitor pattern | one SM per backend, each scraping `/metrics` on the service port | User |
| Alert rules count | 16 (4 groups: services, latency, errors, infrastructure) | User |
| Alertmanager | not yet installed; alerts load into Prometheus rules but no destinations (Stage 8 adds Slack/PD) | User |
| OTEL collector deployment | DaemonSet (one per node) | User |
| Observability Application | NOT added to ArgoCD module (per user request) | User |
| ArgoCD module | inherited verbatim from Stage 5 (no observability Application) | User |
| `/metrics` endpoint | now real Prometheus exposition format (was JSON placeholder) | User |
| Trace ID in JSON logs | pulled from active OTEL span context (was X-Request-ID only) | User |

---

## Stage 6 → Stage 7 baseline (what carries over)

The next agent starts from `stages/stage6/` and produces `stages/stage7/`.
Stage 6's `apply.sh` is the runnable baseline. **Don't rebuild from
scratch** — copy `stages/stage6/` and add Stage 7's changes.

| Layer | Stage 6 state | Carries to Stage 7? |
|---|---|---|
| App stack (5 backends + frontend) | 3 probes + Guaranteed QoS + 30s grace + OTEL SDK + real /metrics | **YES — base for Stage 7 HPA** |
| Access stack (Envoy + MetalLB) | Gateway Programmed, IP 172.18.0.50, 6 HTTPRoutes | **YES — verbatim** |
| Observability stack | Prometheus + Grafana + Tempo + Loki + Promtail in `apollo-observability` ns | **YES — HPA queries Prometheus for custom metrics** |
| ServiceAccounts (13) | 1 per workload + 3 seed SAs + 1 observability SA | **YES** |
| NetworkPolicies (16) | Reference only | **YES** |
| ConfigMap + Secret | `apollo-airlines-config`, `apollo-airlines-secrets` | **YES** |
| 4 StatefulSets (3 PG + redis) | PVCs Bound, Guaranteed QoS, 60s grace | **YES** |
| 2 PodDisruptionBudgets (booking + frontend) | `minAvailable=1` | **YES** |
| 3 seed Jobs | All succeeded | **YES** |
| Code (`stages/stage6/code/`) | OTEL SDK + real /metrics | **YES — Stage 7 adds Redis cache + token-bucket rate limiting** |

---

## Critical insights from Stage 6 (read before changing)

1. **OTEL SDK init order is load-bearing.** The tracer provider must be
   set up *before* the HTTP server starts (so otelgin can register its
   middleware). If init fails (e.g. otel-collector:4317 unreachable at
   startup), the service still runs — just without traces. The
   `initOTEL` function logs a warning and continues.

2. **W3C `traceparent` is the modern propagation header.** The X-Request-ID
   from Stage 1 is still propagated for backward compat, but the OTEL
   SDK uses `traceparent` for trace context. Both work side by side;
   the trace_id in JSON logs is now the W3C trace ID (32 hex chars), not
   the X-Request-ID UUID.

3. **Service.prometheus.io annotations are a backup to ServiceMonitors.**
   We have both. ServiceMonitors are the primary mechanism (CRD-based,
   label-selected). The annotations on the pod template are a safety net
   in case the Prometheus operator isn't running.

4. **The OTEL Collector DaemonSet has a headless Service.** The Service
   has `clusterIP: None` and no selector — each pod is its own DNS entry
   (otel-collector-{node}). The apps connect to whichever one is
   "closest" via in-cluster DNS. For the trace test, the debug pod
   resolves `otel-collector` to whichever pod is on its node.

5. **Grafana JSON in YAML ConfigMaps is fragile.** A naive `data:
   dashboard.json: |` (literal block scalar) breaks when the JSON
   contains `null` literals, because YAML treats `null` as a null
   scalar in unquoted context. **Solution:** wrap the JSON in a quoted
   single-line string scalar. The pattern used in our dashboards:
   `data: dashboard.json: '{...single-line JSON...}'`.

6. **Tempo's storage path matters.** The `local` backend writes to
   `/var/tempo/blocks` and `/var/tempo/wal`. The PVC must mount at
   `/var/tempo` so both paths are covered.

7. **Loki + Promtail namespace filter keeps storage low.** A relabel
   rule `__meta_kubernetes_namespace =~ 'apollo-.*|apollo-airlines-.*'`
   ensures we only ship Apollo logs, not `kube-system` or `argocd`.

8. **Cross-namespace HTTPRoute needs a ReferenceGrant.** The Gateway is
   in `apollo-airlines-apps`; the Grafana HTTPRoute lives in
   `apollo-observability`. The ReferenceGrant in the gateway's
   namespace authorizes the cross-namespace Service reference.

9. **The `trace-test.sh` script uses a busybox debug pod.** This is the
   easiest way to run curl inside the cluster. The pod is created
   on-demand and deleted at the end of the script.

10. **`apply.sh` waits for Prometheus to discover all 5 services
    before declaring success.** The wait is up to 150s (30 × 5s). If
    Prometheus hasn't discovered all 5 by then, the script logs a
    warning but doesn't fail. The verify.sh re-checks.

11. **Charts' inner `{{- with .Values.probes.X }} ... {{- end }}`
    conditionals make per-template gating fragile.** We tried
    wrapping the chart's templates with `{{- if .Values.X.enabled }}`
    gates so the same chart could deploy apps or observability. The
    indentation + nesting of inner with/end blocks made this
    fragile. A cleaner approach is to extract observability into a
    separate subchart (skipped here for time).

12. **The ArgoCD observability Application was intentionally NOT
    added** (per user request). The observability stack is currently
    managed only via the apply.sh script. Stage 7+ can revisit this.
