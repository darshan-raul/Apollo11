# Apollo11 — Agent Context

## What This Project Is

Apollo11 is an **13-phase Kubernetes/cloud-native learning bootstrap** — a curriculum that takes someone from bare Linux basics to production-grade k8s. Each stage is hands-on: you build real services, deploy them to a real cluster, and add operational concerns (networking, storage, monitoring, security, scaling) stage by stage.

**Target learner:** someone with basic Linux knowledge, no prior k8s or cloud-native experience required.

---

## Stage Map

| Phase | Name | Focus |
|---|---|---|
| Launchpad | Docker Compose | 11 services, stub code, local dev |
| Ignition | kind cluster | First pod, kubectl basics, cluster architecture |
| Stage 1 | Liftoff | All 11 services as Deployments, ConfigMaps, Secrets, Jobs |
| Stage 2 | Guidance/N&C | Namespaces, DNS, NetworkPolicies, Ingress |
| Stage 3 | Mission Data | PVCs, StatefulSets, init containers (first persistent storage) |
| Stage 4 | Flight Control | Probes, resource limits, QoS, PodPriority |
| Stage 5 | Payload Integration | Helm charts, Kustomize, GitHub Actions, ArgoCD |
| Stage 6 | Mission Ops | Prometheus, Grafana, Loki, OpenTelemetry |
| Stage 7 | Orbital Maneuvering | HPA, VPA, taints/tolerations, affinity |
| Stage 8 | Command Module | RBAC, SecurityContext, Vault, Sealed Secrets, OPA |
| Stage 9 | Lunar Orbit | EKS/GKE/AKS via Terraform, Cluster Autoscaler, HA |
| Stage 10 | Mission Extensions | Linkerd, Argo Rollouts, DevSecOps, Velero, Chaos Mesh |
| Stage 11 | Towards Mars | CRDs/Operators, k3s homelab, KEDA, Backstage, Goldilocks |

---

## Project Structure

```
Apollo11/
├── SPEC.md                   # Full API contracts, DB schemas, endpoints
├── README.md                 # Top-level stage map
├── AGENTS.md                 # This file
│
├── stages/
│   ├── launchpad/            # Docker Compose — 11 services, stub code
│   │   ├── docker-compose.yml
│   │   └── code/             # auth, catalog, circulation, notification, fines, frontend
│   │
│   ├── ignition/             # kind cluster, first Pod, kubectl basics
│   │   └── README.md
│   │
│   ├── stage1/              # All 11 services as Deployments + Jobs
│   │   ├── README.md
│   │   ├── k8s/             # namespace, configmap, secrets, 22 manifests
│   │   ├── scripts/         # build-images.sh
│   │   └── code/            # copy of launchpad code (stub /health endpoints)
│   │
│   ├── stage2/              # Namespaces, DNS, network policies
│   ├── stage3/              # PVCs, StatefulSets, init containers
│   ├── stage4/              # Probes, resource limits, QoS
│   ├── stage5/              # Helm charts + Kustomize overlays
│   ├── stage6/              # Prometheus + Grafana + OTEL
│   ├── stage7/              # HPA, VPA, affinity
│   ├── stage8/              # RBAC, SecurityContext
│   ├── stage9/              # Cloud provisioning
│   ├── stage10/             # Service mesh, GitOps
│   └── stage11/             # Production-ready
│
└── .hermes/
    └── plans/               # Planning documents
```

**Key design principle:** Each stage's `code/` is a self-contained snapshot. Stage N+1 copies Stage N's code and adds its additions. This keeps every stage independently runnable.

---

## Services (what gets deployed)

| Service | Tech | Port | Database |
|---|---|---|---|
| frontend | Go/Gin | 3000 | — |
| auth | Python/FastAPI | 8080 | auth-postgres (PostgreSQL 15) |
| catalog | Go/Gin | 8081 | catalog-postgres (PostgreSQL 15) + catalog-redis (Redis 7) |
| circulation | Go/Gin | 8082 | circulation-postgres (PostgreSQL 15) |
| notification | Go/Gin | 8083 | notification-redis (Redis 7, port 6380) |
| fines | Go/Gin | 8084 | SQLite on emptyDir (data lost on restart — fixed in stage3) |
| auth-postgres | PostgreSQL 15 | 5432 | — |
| catalog-postgres | PostgreSQL 15 | 5432 | — |
| catalog-redis | Redis 7 | 6379 | — |
| circulation-postgres | PostgreSQL 15 | 5432 | — |
| notification-redis | Redis 7 | 6380 | — |

**Stage 1 storage:** All DBs use `emptyDir` — data lost on pod restart. Stage 3 replaces with PersistentVolumeClaims and StatefulSets.

---

## Stage 1 Details

**Location:** `stages/stage1/`

**k8s manifests** (27 files after removing netpols):
- `namespace.yaml` — `apollo11` namespace
- `configmap.yaml` — service ports, URLs, DB names
- `secrets.yaml` — POSTGRES_PASSWORD, JWT_SECRET
- 5 infra Deployments + 5 Services (postgres × 3, redis × 2)
- 3 Init Jobs (auth, catalog, circulation DB setup) + 3 Init ConfigMaps
- 6 app Deployments + 6 Services (auth, catalog, circulation, notification, fines, frontend)
- `kustomization.yaml` — top-level resource list
- `scripts/build-images.sh` — builds + loads images into kind

**Stage 1 code changes** (vs launchpad):
- All services already have `/health` endpoint (added in launchpad)
- No code changes needed for stage1 — stub code works as-is

**Stage 1 covers:** Namespace, ConfigMap, Secret, Deployment, Service, Job, emptyDir volume, Kustomize. No NetworkPolicies (those start in stage2).

---

## Stage 3 Details

**Location:** `stages/stage3/`

**k8s manifests** (~50 files):
- 3 namespaces (apollo11-infra, apollo11-apps, apollo11-ui)
- StatefulSets: 5 infra DBs (postgres × 3, redis × 2) + fines = 6 total
- Headless Services for all 6 StatefulSets
- VolumeClaimTemplates (1Gi) per StatefulSet
- Init containers inside StatefulSets for DB schema seeding
- 5 app Deployments (auth, catalog, circulation, notification, fines → now STS)
- 1 ui Deployment with nginx sidecar
- NetworkPolicies (ingress allowlisting)
- Ingress for frontend (frontend.apollo11.local)
- Init ConfigMaps for postgres init scripts
- Init Jobs (still present from stage2)

**Key changes from stage2:**
- DB Deployments → StatefulSets with PVCs (data survives restarts)
- Fines Deployment → StatefulSet with PVC (SQLite persists)
- Init Jobs → Init containers inside StatefulSets
- Frontend NodePort → Traefik Ingress
- ClusterIP → Headless services for databases

**Stage 3 code changes** (vs stage2):
- No code changes needed — code doesn't care about StatefulSet vs Deployment

**Stage 3 is complete** — README.md and stage3_test.sh written.

---

## Key Constraints / Conventions

- **Devbox** for environment management — no manual `apt install` for k8s tools
- **Dockerfiles** use multi-stage builds and live in each service's directory
- **YAML frontmatter** on all documentation/readme files
- **Do NOT auto-git-commit** — write files locally, commit only when user explicitly asks
- **User prefers:** concise responses, ASCII diagrams for architecture, comparison tables

---

## Code Evolution Per Stage

| Stage | Code additions |
|---|---|
| launchpad | Base stubs — all services return hardcoded JSON, `/health` exists |
| stage1 | (no code change — k8s deployment layer only) |
| stage2 | Service URLs via k8s DNS |
| stage3 | Volume mount paths for PVCs; init containers for DB seeding |
| stage4 | `/healthz/startup`, `/healthz/live`, `/healthz/ready` probe handlers |
| stage5 | (same as stage4 — packaging only) |
| stage6 | `/metrics` endpoint (Prometheus format); OTEL lib integrated |
| stage7 | TLS-ready handlers; redirect HTTP → HTTPS |
| stage8 | Non-root user in Dockerfiles; service account annotations |
| stage9 | (same as stage8 — GitOps only) |
| stage10 | (same as stage9 — scaling only) |
| stage11 | Full OTEL (traces + metrics + logs), graceful shutdown, structured logging |

---

## Stage Completion Status

| Phase | Status | Details |
|---|---|---|
| Launchpad | ✅ Complete | docker-compose.yml, 6 services, stub code |
| Ignition | ✅ Complete | kind cluster, first Pod, kubectl basics |
| Stage 1 | ✅ Complete | All 11 services as Deployments, Jobs, ConfigMaps, Secrets |
| Stage 2 | ✅ Complete | 3 namespaces, DNS, NetworkPolicies, Ingress, Gateway API |
| Stage 3 | ✅ Complete | k8s manifests, StatefulSets, PVCs, Headless SVCs, init containers, Ingress, README, test script |
| Stage 4 | ⚠️ Partial | code/ copied from stage3 only, no k8s manifests yet |
| Stage 5 | ⚠️ Partial | code/ copied from stage4 only, helm/ and overlays/ dirs exist but empty |
| Stage 6–11 | ❌ Empty | No manifests or code yet |

---

## Devbox Tools

Currently in devbox.json: docker, k3d, kubectl, helm, skaffold, k9s, terraform, argocd

Needed but missing: kind, kustomize, k6, trivy, opa, kyverno, prometheus, grafana, linkerd, velero, cert-manager, vault, sealed-secrets, loki, otel-collector