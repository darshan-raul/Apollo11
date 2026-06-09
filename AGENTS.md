# Apollo11 — Agent Context

## What This Project Is

Apollo11 is a **13-phase Kubernetes/cloud-native learning bootstrap** using **Apollo Airlines** — a flight management system — as the teaching application. Each stage is hands-on: you build real services, deploy them to a real cluster, and add operational concerns (networking, storage, monitoring, security, scaling) stage by stage.

**Target learner:** someone with basic Linux knowledge, no prior k8s or cloud-native experience required.

---

## Stage Map

| Phase | Name | Focus |
|---|---|---|
| Launchpad | Docker Compose | 10 components, stub code, local dev |
| Ignition | kind cluster | First pod, kubectl basics, cluster architecture |
| Stage 1 | Liftoff | All 10 components as Deployments, ConfigMaps, Secrets, Jobs (single-namespace baseline) |
| Stage 2 | Guidance/N&C | **4 manifest sets** — Namespaces, DNS, ServiceAccounts, Headless Services, NetworkPolicies (reference), Ingress (Traefik), Gateway API (Envoy), MetalLB |
| Stage 3 | Mission Data | StatefulSets + 1Gi PVCs for all 4 stateful workloads (3 PG + redis), schema bootstrap via Postgres `/docker-entrypoint-initdb.d/` ConfigMap mount, idempotent seed Jobs. **Envoy Gateway + MetalLB access stack from Stage 2 set 4 carries over verbatim and persists for all later stages.** |
| Stage 4 | Flight Control | Probes, resource limits, QoS, PodDisruptionBudget |
| Stage 5 | Payload Integration | Helm charts, Kustomize, GitHub Actions, ArgoCD |
| Stage 6 | Mission Ops | Prometheus, Grafana, OpenTelemetry |
| Stage 7 | Orbital Maneuvering | HPA, VPA, Redis cache, taints/tolerations, affinity |
| Stage 8 | Command Module | RBAC, SecurityContext, OPA, Vault |
| Stage 9 | Lunar Orbit | EKS/GKE via Terraform, Cluster Autoscaler, HA |
| Stage 10 | Mission Extensions | Linkerd, Argo Rollouts, Chaos Mesh, DevSecOps |
| Stage 11 | Towards Mars | CRDs/Operators, k3s homelab, KEDA |

---

## Apollo Airlines — Services

### App Services (6)

| Service | Tech | Port | Database | Purpose |
|---|---|---|---|---|
| identity | Python/FastAPI | 8080 | identity-db (PostgreSQL 15) | JWT auth, user profiles, passenger management |
| flight | Go/Gin | 8081 | flight-db (PostgreSQL 15) | Flight inventory, seat management |
| booking | Go/Gin | 8082 | booking-db (PostgreSQL 15) | Reservations (flagship service) |
| search | Go/Gin | 8083 | — | Optimised flight search (Redis from Stage 7) |
| notification | Go/Gin | 8084 | — | Event fan-out (Redis from Launchpad) |
| frontend | React/Tailwind | 3000 | — | SPA, served via NGINX in Docker |

### Infrastructure (4)

| Service | Type | Version |
|---|---|---|
| identity-db | PostgreSQL | 15 |
| flight-db | PostgreSQL | 15 |
| booking-db | PostgreSQL | 15 |
| redis | Redis | 7 |

**Total: 10 components in Launchpad.**

---

## Project Structure

```
Apollo11/
├── SPEC.md                   # Full API contracts, DB schemas, endpoints (Apollo Airlines)
├── README.md                 # Top-level stage map
├── AGENTS.md                 # This file
│
├── stages/
│   ├── launchpad/            # Docker Compose — 10 components, stub code
│   │   ├── docker-compose.yml
│   │   ├── README.md
│   │   └── code/             # identity, flight, booking, search, notification, frontend
│   │
│   ├── ignition/             # kind cluster, first Pod, kubectl basics
│   │   └── README.md
│   │
│   ├── stage1/              # All 10 components as Deployments + Jobs
│   │   ├── README.md
│   │   ├── k8s/             # namespace, configmap, secrets, infra/, apps/, jobs/
│   │   ├── scripts/         # build-images.sh
│   │   └── code/            # copy of launchpad code
│   │
│   ├── stage2/              # Namespaces, DNS, NetworkPolicies, Ingress, Gateway API, MetalLB
│   │   ├── README.md
│   │   ├── code/            # shared source (no code changes in stage 2)
│   │   ├── set1-baseline/         # NodePort (no controller)            — 25/25 verify
│   │   ├── set2-ingress/          # Traefik v3 + Ingress + NodePort 30443 — 25/25 verify
│   │   ├── set3-gateway-nodeport/ # Envoy Gateway + port-forward         — 26/26 verify
│   │   └── set4-metallb-gateway/  # Envoy Gateway + MetalLB L2           — 28/28 verify
│   ├── stage3/              # StatefulSets, PVCs, init containers, Headless SVCs
│   │   ├── README.md
│   │   ├── code/            # snapshot of stages/stage2/code/  (no code changes)
│   │   ├── k8s/             # config, serviceaccounts, networkpolicies, apps/, jobs/, gateway/, metallb/
│   │   └── scripts/         # apply.sh, teardown.sh, verify.sh, build-images.sh
│   ├── stage4/              # Probes, resource limits, QoS, PodDisruptionBudget
│   ├── stage4/              # Probes, resource limits, QoS, PodDisruptionBudget
│   ├── stage5/              # Helm charts + Kustomize overlays + GitHub Actions
│   ├── stage6/              # Prometheus + Grafana + OpenTelemetry
│   ├── stage7/              # HPA, VPA, Redis cache, affinity/taints
│   ├── stage8/              # RBAC, SecurityContext, OPA, Vault
│   ├── stage9/              # EKS/GKE Terraform provisioning
│   ├── stage10/             # Linkerd, Argo Rollouts, Chaos Mesh
│   └── stage11/             # CRD operator, k3s, KEDA
│
└── test/                     # Automated verification scripts per stage
```

**Key design principle:** Each stage's `code/` is a self-contained snapshot. Stage N+1 copies Stage N's code and adds its additions. This keeps every stage independently runnable.

---

## Apollo11 vs Apollo11-Docs (Two-Repo Pattern)

**Apollo11** (`/home/darshan/projects/Apollo11/`) — the **code repository**
- All service code, Dockerfiles, Kubernetes manifests, scripts, and stage READMEs live here.
- This is the repo users clone to follow along and run the labs.
- Never modify Apollo11 code based on what's in the docs — the code is the source of truth.

**Apollo11-Docs** (`/home/darshan/projects/apollo11-docs/`) — the **Docusaurus learning site**
- Built with Docusaurus, deployed separately (e.g., Vercel).
- Contains narrative guides, screenshots, step-by-step instructions, architecture diagrams, and explanations.
- Docs reference Apollo11 code by path — the docs don't contain the code itself.
- When updating docs, write detailed instructional content (screenshots, commands, troubleshooting, expected outputs) — don't just summarize. The docs teach; Apollo11 is the lab environment.

**Relationship:** Apollo11 is the lab, apollo11-docs is the textbook. They are separate repos. Apollo11 code changes don't require docs updates (except when behavior changes), but every new topic covered in docs should have corresponding working code in Apollo11.

---

## Stage Details

### Launchpad

**Location:** `stages/launchpad/`

**Components:** 10 total (6 app services + 4 infra)

**Code requirements per service:**
- `/healthz` — liveness probe (returns 200 if process alive)
- `/readyz` — readiness probe (returns 200 only when DB connections + downstream reachability are healthy, 503 otherwise)
- `/metrics` — Prometheus-compatible (`http_requests_total`, `http_request_duration_ms`, `db_connections_active` for stateful services)
- Structured JSON logging: `{"timestamp","level","service","trace_id","span_id","message",...}`
- `X-Request-ID` header propagation (generate if not present, forward on all downstream calls)
- **CORS middleware** on all services (Go and Python) — `Access-Control-Allow-Origin: *`, all methods/headers, 204 for OPTIONS
- **DB connection: always append `?sslmode=disable`** — Go `lib/pq` driver defaults to SSL; PostgreSQL containers in dev have no SSL
- **Graceful `initDB()` with timeout** — use `context.WithTimeout` + `PingContext`; never use infinite retry loops; log errors during retry
- Stub implementations — return hardcoded but valid-appearing JSON

**Seed data (present from first `docker compose up`):**
- 6 airports: BOM, DEL, SIN, DXB, LHR, JFK
- 6 flights: AA101, AA102, AA201, AA202, AA301, AA401 (today + 30 days)
- 2 users: admin@apolloairlines.com/admin123 (ADMIN), passenger@apolloairlines.com/pass123 (PASSENGER)

**Infrastructure init:** PostgreSQL init scripts via `/docker-entrypoint-initdb.d/` pattern.

---

### Stage 1 (Liftoff)

**Location:** `stages/stage1/`

**k8s manifests (27 files):**
- `namespace.yaml` — `apollo-airlines` namespace
- `configmap.yaml` — service ports, internal URLs, database names
- `secrets.yaml` — POSTGRES_PASSWORD, JWT_SECRET
- 4 infra Deployments + Services (identity-db, flight-db, booking-db, redis)
- 3 Init Jobs (identity-db, flight-db, booking-db) + Init ConfigMaps
- 6 app Deployments + Services (identity, flight, booking, search, notification, frontend)
- `kustomization.yaml` — top-level resource list
- `scripts/build-images.sh` — builds + loads images into kind

**Stage 1 code changes vs launchpad:** None (k8s deployment layer only)

---

### Stage 2 (Guidance/N&C)

**Location:** `stages/stage2/`

**Architecture:** Same 10 workloads, **4 self-contained manifest sets** that teach different edge access patterns. Workloads never change between sets — only the "edge" object does.

| Set | Access | Verify |
|---|---|---|
| `set1-baseline` | NodePort (30080–30084), no controller | 25/25 pass |
| `set2-ingress` | Traefik v3 Ingress + NodePort 30443 | 25/25 pass |
| `set3-gateway-nodeport` | Envoy Gateway v1.2.4 + port-forward (ClusterIP) | 26/26 pass |
| `set4-metallb-gateway` | Envoy Gateway v1.2.4 + MetalLB v0.14.5 L2 LoadBalancer | 28/28 pass |

**Namespaces (2, not 3):**
- `apollo-airlines-apps` — identity, flight, booking, search, notification, identity-db, flight-db, booking-db, redis, init jobs
- `apollo-airlines-ui` — frontend

(Original plan had 3 namespaces with infra split out. Collapsed to 2 to avoid
init-job-namespace-mismatch bugs and keep DB hostnames short
e.g. `identity-db` instead of `identity-db.apollo-airlines-infra.svc.cluster.local`.)

**Per-set layout (each set is self-contained, ~30–50 files):**
```
setN-*/
├── README.md                # set-specific concepts, apply/teardown/verify
├── k8s/
│   ├── config/              # 2 namespaces, configmap, secrets
│   ├── serviceaccounts/     # 13 SAs (1 per workload + 3 init jobs)
│   ├── networkpolicies/     # reference only — kindnet does NOT enforce
│   ├── apps/                # 6 app services + 4 infra + 4 headless SVCs
│   ├── jobs/                # 3 init DB jobs
│   ├── ingress/   (set 2)   # Traefik DaemonSet + Ingresses
│   ├── gateway/   (sets 3,4)# Envoy Gateway install + Gateway + HTTPRoutes
│   └── metallb/   (set 4)   # MetalLB install + IP pool + L2 advertisement
└── scripts/
    ├── apply.sh             # build images + apply manifests in order
    ├── teardown.sh          # delete namespaces + controllers
    ├── verify.sh            # 25–28 checks per set
    └── build-images.sh      # per-set frontend VITE_* URLs (baked at build)
```

**Hostnames (sets 2-4):** `frontend.apollo.local`, `identity.apollo.local`,
`flight.apollo.local`, `booking.apollo.local`, `search.apollo.local`

**Headless Services:** `identity-db-headless`, `flight-db-headless`,
`booking-db-headless`, `redis-headless` (`clusterIP: None`) — wired to
StatefulSets in Stage 3.

**ServiceAccounts:** 13 SAs (identity, flight, booking, search, notification,
frontend, identity-db, flight-db, booking-db, redis + 3 init job SAs). No
`Role`/`RoleBinding` yet — those arrive in Stage 8.

**NetworkPolicies:** Manifests provided for reference
(default-deny + per-service allowlist). **NOT applied by `apply.sh`** because
kind's default `kindnet` CNI does not enforce NetworkPolicies. The
educational value is in reading them, not in enforcement.

**Traefik v3.1 IngressController (set 2):** DaemonSet on control-plane,
listens on NodePort 30443. Host header routing across 5 Ingresses.

**Envoy Gateway v1.2.4 (sets 3, 4):**
- `install.yaml` (~1.5MB) bundled in-repo (offline-friendly) — must use
  `kubectl apply --server-side` (exceeds 256KB last-applied-config limit otherwise)
- `install.yaml` does **NOT** create a `GatewayClass` — create it manually:
  `controllerName: gateway.envoyproxy.io/gatewayclass-controller`
- Auto-created Envoy Service is `type: LoadBalancer` by default:
  - Set 3: patch to `ClusterIP` + `kubectl port-forward`
  - Set 4: leave as `LoadBalancer`, MetalLB assigns IP
- Cross-namespace HTTPRoute attachments need `parentRef.namespace` +
  `ReferenceGrant` in target namespace
- 6 HTTPRoutes + 1 ReferenceGrant (frontend in `ui` ns → Gateway in `apps` ns)

**MetalLB v0.14.5 native (set 4):**
- L2 mode (ARP/NDP) — no router config required
- `metallb-native.yaml` (~1900 lines) bundled in-repo — use
  `kubectl apply --server-side --force-conflicts` (webhook manages its own CA)
- IP pool: `172.18.0.50–100` on default kind docker network (must not
  overlap with kind node IPs)
- Wait for webhook controller pod to be `1/1` before creating IPAddressPool

**Service type rules across sets:**
- Set 1: `type: NodePort + nodePort: 30xxx`
- Sets 2/3/4: `type: ClusterIP` (NodePort removed — kubectl rejects apply
  if `nodePort` is set with `type: ClusterIP`)

**Frontend image:** VITE\_\* API URLs are baked at build time. Each set
rebuilds the frontend image with its own URL pattern (NodePort, hostname+port,
or MetalLB IP). `apply.sh` handles both build and kind load.

**Stage 2 code changes vs stage1:** None (networking layer only — `stages/stage2/code/` is a snapshot of `stages/stage1/code/`).

---

### Stage 3 (Mission Data)

**Location:** `stages/stage3/`

**Architecture:** Same 10 workloads + same Envoy Gateway + MetalLB access stack as Stage 2 set 4. The 4 stateful workloads (`identity-db`, `flight-db`, `booking-db`, `redis`) move from `Deployment` + `emptyDir` to `StatefulSet` + `1Gi PVC`. App Deployments, frontend, gateway, MetalLB, ServiceAccounts, NetworkPolicies are **unchanged**. The Stage 2 set-4 access stack is the **persisted baseline for all later stages** (4–11).

| Group | Files | What |
|---|---|---|
| `k8s/config/` | 3 | Namespaces, ConfigMap, Secret (verbatim from set 4) |
| `k8s/serviceaccounts/` | 1 | 13 SAs (verbatim from set 4) |
| `k8s/networkpolicies/` | 16 | Reference only (verbatim from set 4) |
| `k8s/apps/identity-db/` | 4 | `*-sts.yaml` (StatefulSet + 1Gi VCT + init SQL mounted at `/docker-entrypoint-initdb.d`), `*-svc.yaml` (ClusterIP), `*-svc-headless.yaml`, `*-init-script.yaml` (ConfigMap) |
| `k8s/apps/flight-db/` | 4 | same shape (UNIQUE on `(flight_number, departure_time)` so the same flight can fly daily) |
| `k8s/apps/booking-db/` | 4 | same shape |
| `k8s/apps/redis/` | 3 | `redis-sts.yaml` (with AOF enabled), `redis-svc.yaml`, `redis-svc-headless.yaml` |
| `k8s/apps/{identity,flight,booking,search,notification,frontend}/` | 12 | Unchanged Deployment + Service |
| `k8s/jobs/` | 6 | 3 × `seed-*.yaml` Jobs + 3 × `*-db-seed` ConfigMaps (idempotent `ON CONFLICT DO NOTHING`) |
| `k8s/gateway/` | 10 | Verbatim from set 4 (Envoy Gateway install + GatewayClass + Gateway + 6 HTTPRoutes + ReferenceGrant) |
| `k8s/metallb/` | 2 | Verbatim from set 4 (install + IPAddressPool + L2Advertisement) |
| `scripts/` | 4 | `apply.sh` (10 steps, waits for StatefulSets before jobs), `teardown.sh` (deletes namespaces + Gateway + controllers, ordered to avoid webhook hangs), `verify.sh` (53 checks), `build-images.sh` |

**Storage:** `storageClassName` is **intentionally omitted** from `volumeClaimTemplates` — uses kind's default `local-path` StorageClass. PVCs are `ReadWriteOnce, 1Gi`. PVs are node-local on the kind worker. Reclaim policy is `Delete` (default), so deleting the PVC reclaims the local-path volume.

**Schema bootstrap (entrypoint hook, not init container):** The schema (CREATE TABLE) is mounted as a ConfigMap at `/docker-entrypoint-initdb.d/init.sql` inside the Postgres container, with `PGDATA=/var/lib/postgresql/data/pgdata`. The official Postgres image's entrypoint runs the SQL during `initdb` on first start (empty PVC). On every subsequent restart, the data dir is non-empty and the entrypoint skips both `initdb` and `/docker-entrypoint-initdb.d/`. **Why not a custom init container:** that approach deadlocks — the init's `pg_isready` against `127.0.0.1` waits for the main container, but the kubelet gates the main container on init's success. The entrypoint hook is the standard Postgres pattern and doesn't have this issue.

**Seed jobs:** 3 one-shot Jobs (`seed-identity-db`, `seed-flight-db`, `seed-booking-db`) that insert seed data using `ON CONFLICT DO NOTHING`. The `seed-booking-db` Job is intentionally near-empty (booking has no seed data) but kept to prove the schema-applied and to keep the pattern uniform.

**Stable pod identity:** The StatefulSet `serviceName` is wired to the existing headless services (`identity-db-headless`, `flight-db-headless`, `booking-db-headless`, `redis-headless`). Pods get FQDNs like `identity-db-0.apollo-airlines-apps.svc.cluster.local` for direct pod-to-pod addressing (used by the StatefulSet controller, not by app code).

**Why entrypoint hook vs Job for schema:** The entrypoint runs the SQL once on first start of the pod (when the data dir is empty). A Job runs once per cluster creation — if the StatefulSet pod moves to a fresh node with an empty PVC, the entrypoint re-applies the schema (idempotently). Seed stays as a Job because re-inserting 186 flight rows on every restart is wasteful (even with `ON CONFLICT DO NOTHING`).

**Code changes vs stage2:** None. `stages/stage3/code/` is a snapshot of `stages/stage2/code/`. App code doesn't know whether the DB is behind a Deployment or StatefulSet.

---

### Stage 4 (Flight Control)

**Location:** `stages/stage4/`

**k8s manifest changes:**
- All Deployments: `livenessProbe`, `readinessProbe`, `startupProbe`
- All Deployments: `resources.requests` and `resources.limits`
- PodDisruptionBudget for frontend and booking

**Code changes vs stage3:**
- `/healthz/startup` probe handler (k8s sends requests during startup)
- `/healthz/live` probe handler (kubelet checks every 10s)
- `/healthz/ready` probe handler (kubelet checks before routing traffic)
- Graceful shutdown on SIGTERM

---

### Stage 5 (Payload Integration)

**Location:** `stages/stage5/`

**k8s manifest changes:** None (packaging layer)

**New files:**
- `helm/apollo-airlines/` — Helm chart with values.yaml, templates
- `overlays/dev/` — Kustomize overlay for local dev
- `overlays/staging/` — Kustomize overlay for staging
- `overlays/prod/` — Kustomize overlay for prod-like
- `.github/workflows/deploy.yml` — GitHub Actions workflow

**Code changes vs stage4:** None (packaging only)

---

### Stage 6 (Mission Ops)

**Location:** `stages/stage6/`

**k8s manifest changes:**
- prometheus-operator with ServiceMonitor per service
- Grafana dashboard for booking service latency
- OTEL collector daemonset
- Loki for log aggregation

**Code changes vs stage5:**
- Full `/metrics` endpoint with all required Prometheus metrics
- OTEL SDK integrated (traces + metrics)
- `trace_id` and `span_id` fields already present in logs since launchpad — now propagated through all calls

---

### Stage 7 (Orbital Maneuvering)

**Location:** `stages/stage7/`

**k8s manifest changes:**
- HPA for search service (CPU-based, min 2 max 10 replicas)
- VPA for search service
- Redis Deployment becomes StatefulSet with PVC

**Code changes vs stage6:**
- Search Service: Redis caching (key: `search:{origin}:{destination}:{date}`, TTL 5min)
- `X-Cache: HIT/MISS` header on search responses
- All Go services: graceful shutdown fully implemented

---

### Stage 8 (Command Module)

**Location:** `stages/stage8/`

**k8s manifest changes:**
- RBAC: viewer role for passengers, admin role for flight management
- SecurityContext on all pods: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`
- OPA Gatekeeper policies for pod security standards
- Vault integration for secret management
- NetworkPolicies tightened further

**Code changes vs stage7:**
- Non-root user in all Dockerfiles
- Service account annotations on pods
- Trace context propagation fully wired

---

### Stage 9 (Lunar Orbit)

**Location:** `stages/stage9/`

**New files:**
- `terraform/` — main.tf with EKS + GKE modules
- `terraform/modules/eks/` — cluster, node groups
- `terraform/modules/gke/` — cluster, node pools
- `terraform/modules/vpc/` — VPC, subnets
- `terraform/modules/ingress/` — ALB/NLB + Ingress
- `scripts/deploy.sh` — apply terraform, deploy k8s manifests

**Code changes vs stage8:** None (cloud provisioning only)

---

### Stage 10 (Mission Extensions)

**Location:** `stages/stage10/`

**k8s manifest changes:**
- Linkerd service mesh install + pod annotations
- Argo Rollouts for booking and search services
- Canary deployment strategy for search service
- Chaos Mesh for fault injection on booking service
- Velero for backup/restore

**Code changes vs stage9:** None (service mesh + progressive delivery)

---

### Stage 11 (Towards Mars)

**Location:** `stages/stage11/`

**New files:**
- Custom K8s operator for flight status management (Go)
- KEDA scaledobject for booking service (event-driven scaling based on booking rate)
- k3s homelab setup guide
- Backstage integration

**Code changes vs stage10:**
- Custom operator for flight status CRD
- KEDA scaler trigger configured
- Graceful shutdown fully implemented across all services

---

## Code Evolution Per Stage

| Stage | Code additions |
|---|---|
| launchpad | Base stubs — all services return hardcoded JSON. `/healthz`, `/readyz`, `/metrics` implemented. Structured logging with trace_id/span_id fields. X-Request-ID propagation. CORS middleware on all Go services. `addSSLMode()` helper for PostgreSQL connections (`?sslmode=disable`). `initDB()` uses `context.WithTimeout(15s)` + `PingContext` + error logging (no more infinite retry loops). `sql.NullString` for nullable DB columns. **Frontend upgraded to React/Tailwind CSS** (modern airline UI, VITE env vars for API URLs, multi-stage Docker build). Admin panel pages (Dashboard, Flights CRUD, Bookings view). |
| stage1 | (no code change — k8s deployment layer only) |
| stage2 | (no code change — networking layer only) |
| stage3 | (no code change — storage layer only) |
| stage4 | `/healthz/startup` probe handler (k8s sends requests during startup). `/healthz/live` probe handler (kubelet checks every 10s). `/healthz/ready` probe handler (kubelet checks before routing traffic). Graceful shutdown on SIGTERM. **Frontend: Go stub replaced with React/Tailwind app** (multi-stage Docker build). |
| stage5 | (no code change — packaging layer only) |
| stage6 | Full `/metrics` endpoint with all required Prometheus metrics. OTEL SDK integrated (traces + metrics). `trace_id` and `span_id` fields already present in logs since launchpad — now propagated through all calls. |
| stage7 | Search Service: Redis caching (key: `search:{origin}:{destination}:{date}`, TTL 5min). `X-Cache: HIT/MISS` header on search responses. All Go services: graceful shutdown fully implemented. |
| stage8 | Non-root user in all Dockerfiles. Service account annotations. Trace context propagation fully wired. |
| stage9 | (no code change — cloud provisioning layer only) |
| stage10 | (no code change — service mesh + progressive delivery only) |
| stage11 | Flight status CRD operator. KEDA scaler trigger configured. Graceful shutdown fully implemented across all services. |

---

## Key Constraints / Conventions

- **Devbox** for environment management — no manual `apt install` for k8s tools
- **Dockerfiles** use multi-stage builds and live in each service's directory
- **Go services:** `golang:1.22-alpine` — flight, booking, search, notification
- **Python service:** `python:3.12-slim` — identity
- **Frontend:** `node:20-alpine` for build, `nginx:alpine` for serving
- **PostgreSQL:** `postgres:15-alpine`
- **Redis:** `redis:7-alpine`
- **YAML frontmatter** on all documentation/readme files
- **Do NOT auto-git-commit** — write files locally, commit only when user explicitly asks
- **No npm on host** — frontend builds happen inside Docker (multi-stage: node builds → nginx serves)
- **User prefers:** concise responses, ASCII diagrams for architecture, comparison tables

---

## Devbox Tools

Currently in devbox.json: docker, k3d, kubectl, helm, skaffold, k9s, terraform, argocd

Needed but missing: kind, kustomize, k6, trivy, opa, kyverno, prometheus, grafana, linkerd, velero, cert-manager, vault, sealed-secrets, loki, otel-collector

---

## Stage Completion Status

| Phase | Status | Details |
|---|---|---|
| Launchpad | ✅ Complete | React/Tailwind frontend, Docker Compose, 10 components |
| Ignition | ✅ Complete | kind cluster, first Pod, kubectl basics |
| Stage 1 | ✅ Complete | All 10 components as Deployments + Jobs, single namespace `apollo-airlines` |
| Stage 2 | ✅ Complete | 4 manifest sets verified: NodePort 25/25, Traefik 25/25, Envoy Gateway 26/26, Envoy+MetalLB 28/28 |
| Stage 3 | ✅ Complete | 4 StatefulSets + PVCs + entrypoint-hook schema + seed jobs, 53/53 verify (Envoy+MetalLB access stack persists for stages 4–11) |
| Stage 4–11 | ⚠️ Pending | Scope defined in AGENTS.md, not yet implemented |

---

## Observability Trace Design (Stage 6+)

The trace for a Create Booking request:

```text
Booking Service (root span)
    │
    ├── Identity Service: GET /api/users/{id}
    │
    ├── Flight Service: GET /api/flights/{id}
    │
    ├── Flight Service: PATCH /api/flights/{id}/seats
    │
    ├── Booking DB: INSERT bookings
    │
    └── Notification Service: POST /api/notify
```

Total spans: 6 spans across 3 services + 1 DB span.

This single trace demonstrates:
- Cross-service context propagation
- Database query timing
- Downstream dependency latency
- Failure points for fault injection (Stage 10)

---

## Booking Service — Flagship Workflow

The Booking Service is the primary vehicle for teaching distributed systems concepts:
- Stage 1-3: Deploy and observe basic health
- Stage 4: Reliable restarts with probes
- Stage 6: OTEL tracing across service boundaries
- Stage 7: Redis caching on search (downstream of booking workflow)
- Stage 9: Load testing with k6
- Stage 10: Chaos injection + service mesh fault injection

---

## Kubernetes Namespace Structure

| Namespace | Contents | Stages |
|---|---|---|
| apollo-airlines | All 10 components in a single namespace | Stage 1, Launchpad (compose) |
| apollo-airlines-apps | identity, flight, booking, search, notification + all DBs/redis + init jobs | Stage 2+ |
| apollo-airlines-ui | frontend | Stage 2+ |

Note: Stage 2 collapsed the originally-planned 3-namespace layout
(`infra`/`apps`/`ui`) down to 2 (`apps`/`ui`) — see Stage 2 details above.

---

## Port Map

| Service | Port | Notes |
|---|---|---|
| frontend | 3000 | React SPA |
| identity | 8080 | FastAPI |
| flight | 8081 | Go/Gin |
| booking | 8082 | Go/Gin |
| search | 8083 | Go/Gin |
| notification | 8084 | Go/Gin |
| identity-db | 5432 | PostgreSQL |
| flight-db | 5432 | PostgreSQL (separate PVC) |
| booking-db | 5432 | PostgreSQL (separate PVC) |
| redis | 6379 | Redis 7 |

---

## Seed Data (Always Present)

Airports: BOM, DEL, SIN, DXB, LHR, JFK

Flights: AA101, AA102, AA201, AA202, AA301, AA401 (today + 30 days, deterministic UUIDs)

Users:
- admin@apolloairlines.com / admin123 (ADMIN)
- passenger@apolloairlines.com / pass123 (PASSENGER)