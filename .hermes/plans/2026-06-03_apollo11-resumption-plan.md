# Apollo11 — Resumption Plan

## Current State

```
stages/
├── liftoff/          ✅ docker-compose.yml complete (11 services, valid YAML)
│   └── code/         ✅ All 6 microservices + Dockerfiles + init.sql
├── stage1/           ⚠️  k8s/ dir exists, no manifests yet
├── stage2–stage4/     ❌  k8s/ dirs + code/ copies exist, nothing else
├── stage5/           ⚠️  helm/ + overlays/ dirs exist, code/ exists
├── stage6–stage10/   ❌  same as stage2
└── stage11/          ⚠️  k8s/ dir exists, code/ exists
```

All stage directories (1–11) have `./code/` copied from liftoff. Stage 1 and stage 5 have placeholder k8s/helm dirs.

---

## What Each Stage Needs

### Liftoff ✅
- **k8s manifests:** None (Docker Compose only)
- **code:** Complete stubs — all services return hardcoded JSON
- **test:** `docker compose up -d && curl localhost:3000`

### Stage 1 — Cluster Bootstrap
- **k8s manifests:** k3d cluster + imperative deploy → declarative manifests
  - 3 StatefulSets (postgres × 3), 2 Deployments (redis × 2), 5 Deployments (app services)
  - 5 Services (ClusterIP), 1 NodePort (frontend)
  - ConfigMaps for env vars, Secrets for DB passwords
- **code changes:** Add `/health` and `/ready` endpoints to all services
- **learns:** kubectl, Pods, Deployments, Services, StatefulSets, ConfigMaps, Secrets

### Stage 2 — Namespace Isolation + Service Discovery
- **k8s manifests:** Namespace per service, network policies, DNS-based service discovery
- **code changes:** Service URLs switch from env vars to k8s DNS (`http://auth.default.svc.cluster.local:8080`)
- **learns:** Namespaces, DNS resolution, network policies basics

### Stage 3 — Persistent Storage
- **k8s manifests:** PVCs for all stateful services, volume mounts, init containers for DB seeding
- **code changes:** Persist search cache key pattern to Redis volumes; SQLite for fines
- **learns:** PersistentVolumeClaim, volume mounting, init containers

### Stage 4 — Probes & Resource Management
- **k8s manifests:** Startup, liveness, readiness probes on all Deployments; resource requests/limits; PodDisruptionBudgets
- **code changes:** Implement `/healthz/startup`, `/healthz/live`, `/healthz/ready` handlers
- **learns:** Probe patterns, resource QoS, PDBs

### Stage 5 — Packaging (Helm + Kustomize)
- **k8s manifests:** Convert all YAML to Helm chart with `Chart.yaml`, `values.yaml`; create `overlays/dev`, `overlays/staging`, `overlays/prod` with Kustomize
- **code changes:** None (same as stage4)
- **learns:** Helm templating, Kustomize overlays, environment promotion

### Stage 6 — Observability
- **k8s manifests:** Prometheus + Grafana stack; ServiceMonitors; PrometheusRules
- **code changes:** Add `/metrics` endpoint (Prometheus format); integrate OTEL for traces
- **learns:** Prometheus scrape config, metrics, dashboards, alerting rules

### Stage 7 — Ingress & TLS
- **k8s manifests:** Ingress controller, Ingress resources, TLS certs (self-signed for dev)
- **code changes:** Add `/metrics` (if not done), ensure `/health` works behind ingress
- **learns:** Ingress, TLS, hostname routing

### Stage 8 — Security (RBAC, SecurityContext)
- **k8s manifests:** ServiceAccounts, RBAC Roles/RoleBindings, SecurityContext on pods, PodSecurityPolicies, NetworkPolicies
- **code changes:** Ensure services run as non-root; add service account annotations
- **learns:** RBAC, security contexts, pod security standards

### Stage 9 — GitOps with ArgoCD
- **k8s manifests:** ArgoCD Application + ApplicationSet; GitHub Actions workflow to push manifests
- **code changes:** None
- **learns:** ArgoCD setup, GitOps workflow, image tagging strategy

### Stage 10 — Scaling (HPA, VPA)
- **k8s manifests:** HorizontalPodAutoscaler for all app Deployments; VPA config
- **code changes:** Ensure `/health` is lightweight for HPA metric checks
- **learns:** HPA, VPA, scale metrics (CPU/memory/custom)

### Stage 11 — Production Ready
- **k8s manifests:** All prior stages combined: Helm, ArgoCD, HPA, RBAC, ingress, TLS, monitoring
- **code changes:** Full OTEL integration (traces + metrics + logs), graceful shutdown, structured logging
- **learns:** Putting it all together

---

## Recommended Work Order

```
Phase 1: Validate liftoff works
  → docker compose up -d
  → fix any service errors

Phase 2: Build stage1 (foundation — everything else depends on it)
  → k3d cluster, k8s manifests for all services
  → add /health endpoints to code

Phase 3: Build stage2–4 (core k8s primitives)
  → stage2: namespaces, DNS
  → stage3: PVCs, init containers
  → stage4: probes, resources

Phase 4: Build stage5 (packaging — unlocks stage6+)
  → Helm chart + Kustomize overlays

Phase 5: Build stage6–10 (operations layer)
  → monitoring → ingress → security → GitOps → scaling

Phase 6: Build stage11 (production)
  → full OTEL, all features combined
```

---

## Key Decisions to Make Before Proceeding

1. **Stage1 approach:** Should stage1 manifest deploy all services via single `kustomization.yaml` or separate files per service?
2. **Local k8s:** k3d vs minikube vs kind — which for the learner? (k3d is fastest and supports LoadBalancer)
3. **Helm in stage5:** Should the chart be under `stages/stage5/helm/` or top-level `helm/`?
4. **Secrets management:** Start with k8s Secrets in stage1, or defer to stage2 to keep stage1 simpler?
5. **OTel timing:** Stage4 or stage6 for first traces? Stage4 keeps probe code cleaner; stage6 is more natural grouping