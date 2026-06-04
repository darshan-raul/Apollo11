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
| Stage 1 | Liftoff | All 10 components as Deployments, ConfigMaps, Secrets, Jobs |
| Stage 2 | Guidance/N&C | Namespaces, DNS, NetworkPolicies, Ingress (Traefik) |
| Stage 3 | Mission Data | PVCs, StatefulSets, init containers (first persistent storage) |
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
| frontend | React/Node | 3000 | — | SPA, served via NGINX in Docker |

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
│   ├── stage2/              # Namespaces, DNS, NetworkPolicies, Ingress (Traefik)
│   ├── stage3/              # StatefulSets, PVCs, init containers, Headless SVCs
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

**k8s manifests:**
- 3 namespaces: `apollo-airlines-infra`, `apollo-airlines-apps`, `apollo-airlines-ui`
- NetworkPolicies: default-deny + per-service allowlist
- Headless Services for all 4 infra DBs
- Traefik Ingress for frontend (hostname: `frontend.apolloairlines.local`)
- Gateway API HTTPRoute for catalog service
- ServiceAccounts for all pods

**Stage 2 code changes vs stage1:** None (networking layer only)

---

### Stage 3 (Mission Data)

**Location:** `stages/stage3/`

**k8s manifests (~50 files):**
- All 4 infra DBs become StatefulSets with VolumeClaimTemplates (1Gi)
- Headless Services for all StatefulSets
- Init containers inside StatefulSets for DB schema seeding (replaces init Jobs for schema)
- Init Jobs still present for data seeding (runs once)
- Traefik Ingress (unchanged from stage2)
- NetworkPolicies (unchanged from stage2)

**Stage 3 code changes vs stage2:** None (storage layer only — code doesn't care about StatefulSet vs Deployment)

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
| launchpad | Base stubs — all services return hardcoded JSON. `/healthz`, `/readyz`, `/metrics` implemented. Structured logging with trace_id/span_id fields. X-Request-ID propagation. |
| stage1 | (no code change — k8s deployment layer only) |
| stage2 | (no code change — networking layer only) |
| stage3 | (no code change — storage layer only) |
| stage4 | `/healthz/startup`, `/healthz/live`, `/healthz/ready` probe handlers. Graceful shutdown. |
| stage5 | (no code change — packaging layer only) |
| stage6 | Full `/metrics` endpoint. OTEL SDK integrated. Trace context propagates through all calls. |
| stage7 | Search Service: Redis caching. X-Cache: HIT/MISS header. Graceful shutdown fully implemented. |
| stage8 | Non-root user in Dockerfiles. Service account annotations. |
| stage9 | (no code change — cloud provisioning layer only) |
| stage10 | (no code change — service mesh + progressive delivery only) |
| stage11 | Flight status CRD operator. KEDA scaledobject. Graceful shutdown. |

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
| Launchpad | 🔴 Pending | Apollo Airlines replacing library system |
| Ignition | ✅ Complete | kind cluster, first Pod, kubectl basics |
| Stage 1 | 🔴 Pending | Apollo Airlines k8s manifests |
| Stage 2–11 | ⚠️ Pending | Scope defined in SPEC.md, not yet implemented |

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

| Namespace | Contents |
|---|---|
| apollo-airlines | Launchpad / single-namespace stages |
| apollo-airlines-infra | DB StatefulSets (stage2+) |
| apollo-airlines-apps | App service Deployments (stage2+) |
| apollo-airlines-ui | Frontend Deployment (stage2+) |

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