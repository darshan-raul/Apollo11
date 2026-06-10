---
title: "Stage 5: Payload Integration — Helm + Kustomize + GitHub Actions"
description: "Package the Stage 4 (probes + QoS + graceful SIGTERM) workloads as a production-ready Helm chart with Kustomize overlays for dev/staging/prod and a CI workflow that builds + pushes images to GHCR."
---

# Stage 5: Payload Integration

**Goal:** Make Apollo Airlines **deployable, versioned, and CI-driven**. The
Stage 4 workloads (6 app Deployments + 4 StatefulSets + PDBs + 13 SAs) are
packaged as a single Helm chart with Kustomize overlays for environment
variation, and a GitHub Actions workflow that lints, builds, and pushes
images to GHCR on every change to `main`.

| | |
|---|---|
| **New concept** | Helm chart structure, values templating, Kustomize base + overlays, GitHub Actions matrix builds, GHCR image registry, GitOps-ready packaging |
| **Workloads changed** | None at the workload level — Stage 5 is a packaging layer. All 10 workloads are unchanged from Stage 4. |
| **Workloads unchanged** | Probes, Guaranteed QoS, graceful SIGTERM, PDBs, 13 SAs, 3 PG + 1 Redis StatefulSets, seed jobs |
| **Code changes** | None (snapshot of `stages/stage4/code/`) |
| **Verify target** | **~70 checks pass** |

---

## What changed vs Stage 4

### 1. Helm chart (production deployment path)

The chart at `stages/stage5/helm/apollo11/` is a single source of truth
for the cluster. `helm install` provisions everything:

```
helm/apollo11/
├── Chart.yaml                          (metadata: name, version 1.0.0)
├── values.yaml                         (configurable defaults)
├── values-dev.yaml                     (env-specific: 1 replica, :dev tag, no PDBs)
├── values-staging.yaml                 (env-specific: 2 replicas, :latest tag, no PDBs)
├── values-prod.yaml                    (env-specific: 3 replicas, :v1.0.0 tag, full PDBs, GHCR pull)
├── bundles/
│   ├── envoy-gateway-install.yaml      (v1.2.4, 2.4MB — offline-friendly)
│   └── metallb-native.yaml             (v0.14.5, 67KB — offline-friendly)
└── templates/
    ├── _helpers.tpl                    (label, selector, name helpers)
    ├── config/
    │   ├── namespace.yaml              (2 ns: apps, ui)
    │   ├── serviceaccount.yaml         (13 SAs)
    │   ├── configmap.yaml
    │   └── secrets.yaml
    ├── infra/
    │   ├── postgres.yaml               (3 PG StatefulSets + headless + init SQL)
    │   └── redis.yaml                  (1 Redis StatefulSet + headless)
    ├── apps/
    │   ├── identity.yaml
    │   ├── flight.yaml
    │   ├── booking.yaml                (flagship tier: 200m/256Mi)
    │   ├── search.yaml
    │   └── notification.yaml
    ├── ui/
    │   └── frontend.yaml
    ├── pdb/
    │   └── pdb.yaml                    (booking-pdb, frontend-pdb)
    ├── jobs/
    │   └── seed.yaml                   (3 idempotent seed Jobs)
    └── gateway/
        ├── gateway.yaml                (GatewayClass + Gateway)
        ├── httproutes.yaml             (6 HTTPRoutes + 1 ReferenceGrant)
        ├── envoy-install.yaml          (renders bundles/envoy-gateway-install.yaml)
        ├── metallb.yaml                (IPAddressPool + L2Advertisement)
        └── metallb-install.yaml        (renders bundles/metallb-native.yaml)
```

**One `helm install` gives you:**

- 2 namespaces (`apollo-airlines-apps`, `apollo-airlines-ui`)
- 13 ServiceAccounts
- 3 Postgres StatefulSets + 3 headless SVCs + 3 init SQL ConfigMaps
- 1 Redis StatefulSet + 1 headless SVC
- 6 app Deployments + 1 frontend Deployment
- 2 PodDisruptionBudgets (booking, frontend)
- 3 idempotent seed Jobs
- Envoy Gateway install + GatewayClass + Gateway
- 6 HTTPRoutes + 1 cross-namespace ReferenceGrant
- MetalLB install + IPAddressPool + L2Advertisement

**Tunable via `values.yaml`:**

| Setting | Default | Purpose |
|---|---|---|
| `image.tag` | `latest` | Pin to a specific version (e.g. `v1.2.3`) |
| `image.repository` | `apollo11` | Override registry (e.g. `ghcr.io/darshan/apollo11`) |
| `apps.<name>.replicas` | 2 | Per-app replica count |
| `apps.<name>.tier` | `default` | Resource tier: `default` (100m/128Mi), `flagship` (200m/256Mi), `low` (50m/64Mi), `edge` (50m/64Mi) |
| `pdb.enabled` | `true` | Toggle both PodDisruptionBudgets |
| `gateway.enabled` | `true` | Bundle the Envoy Gateway access stack |
| `metallb.enabled` | `true` | Bundle MetalLB |
| `metallb.ipPool.addresses` | `172.18.0.50-100` | LoadBalancer IP range |
| `gateway.hostSuffix` | `apollo.local` | Hostname suffix for all HTTPRoutes |

### 2. Kustomize overlays (dev-friendly alternative)

```
overlays/
├── base/                # plain manifests for 6 apps + frontend
│   ├── kustomization.yaml
│   ├── apps/
│   │   ├── identity.yaml
│   │   ├── flight.yaml
│   │   ├── booking.yaml
│   │   ├── search.yaml
│   │   └── notification.yaml
│   └── ui/
│       ├── kustomization.yaml
│       └── frontend.yaml
├── dev/                 # 1 replica, tag=dev
├── staging/             # 2 replicas, tag=latest
└── prod/                # 3 replicas, tag=v1.0.0, +PDBs
```

The Kustomize base is a **plain manifest subset** of the chart — it only
contains the 6 app Deployments + frontend. The chart's StatefulSets, seed
jobs, and access stack are not part of the Kustomize path (apply.sh
combines the overlay with the chart's infra templates so the apps can
still resolve `identity-db:5432` etc.).

### 3. GitHub Actions CI

`.github/workflows/main.yml` (replaces the stock "Hello, world" stub):

1. **Lint job** — `helm lint`, `helm template` smoke render, `kubectl kustomize build` for all 3 overlays, `shellcheck` on the scripts.
2. **Build job** — Matrix build of all 6 service images using `docker/build-push-action@v6` with GHA cache. Frontend gets `VITE_*` URLs from `values.yaml` injected as build args.
3. **Push job** — Only on `main` push or `v*` tag, push to GHCR with `:sha-<gitsha>` + `:latest` tags.

No deploy step — ArgoCD (separate tooling, mentioned in `AGENTS.md`) handles deploys from GHCR.

---

## Environment Comparison

| Setting | Dev | Staging | Prod |
|---|---|---|---|
| **Deployment path** | Kustomize overlay (`apply.sh --mode kustomize --env dev`) | Kustomize overlay (`--env staging`) | Helm chart (recommended) or Kustomize (`--env prod`) |
| **Replicas per app** | 1 | 2 | 3 |
| **Image tag** | `:dev` | `:latest` | `:v1.0.0` (pinned) |
| **PodDisruptionBudgets** | No | No | Yes (`minAvailable: 2`) |
| **Access stack** | Yes (via chart components during `apply.sh`) | Yes | Yes |
| **StatefulSets** | Yes | Yes | Yes |
| **Cost** | Lowest | Medium | Highest |

**Dev** is the cheapest cluster — 1 replica each, dev image tag, no PDBs.
Use it for local iteration and feature branches.

**Staging** mirrors prod's default replica count but with rolling `:latest`
images. Use it for integration testing.

**Prod** is the recommended Helm install with pinned tags, 3 replicas, and
PDBs for booking + frontend. Use it for the actual production cluster.

---

## Usage

### Helm (production path)

```bash
cd stages/stage5

# One-shot install with defaults (values.yaml, tag=latest)
bash scripts/apply.sh

# Use the env-specific values file
bash scripts/apply.sh --env dev       # values-dev.yaml — 1 replica, :dev tag
bash scripts/apply.sh --env staging   # values-staging.yaml — 2 replicas, :latest
bash scripts/apply.sh --env prod      # values-prod.yaml — 3 replicas, :v1.0.0, GHCR

# Override the tag the env file pins
bash scripts/apply.sh --env prod --tag v1.2.3

# Skip the docker build step (use pre-loaded images)
bash scripts/apply.sh --skip-build

# Tear down
bash scripts/teardown.sh                # uninstall the helm release
bash scripts/teardown.sh --purge        # also delete namespaces + access stack
```

### Kustomize (dev-friendly path)

```bash
cd stages/stage5

# Dev overlay (1 replica, :dev tag)
bash scripts/apply.sh --mode kustomize --env dev

# Staging overlay
bash scripts/apply.sh --mode kustomize --env staging

# Prod overlay
bash scripts/apply.sh --mode kustomize --env prod

# Tear down
bash scripts/teardown.sh --mode kustomize --env dev
```

### Verify

```bash
cd stages/stage5

# Auto-detect mode
bash scripts/verify.sh

# Explicit
bash scripts/verify.sh --mode helm
bash scripts/verify.sh --mode kustomize --env prod
```

### CI

Push to `main` or open a PR — the workflow at `.github/workflows/main.yml`
runs lint + build automatically. On `main` pushes it also pushes to GHCR.

---

## Files

```
stage5/
├── code/                            # snapshot of stages/stage4/code/
│   ├── identity/                    (Python/FastAPI)
│   ├── flight/                      (Go/Gin)
│   ├── booking/                     (Go/Gin — flagship)
│   ├── search/                      (Go/Gin)
│   ├── notification/                (Go/Gin)
│   └── frontend/                    (React/Tailwind → NGINX)
├── helm/apollo11/                   # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── bundles/                     (Envoy + MetalLB install YAMLs)
│   └── templates/                   (27 templates)
├── overlays/                        # Kustomize overlays
│   ├── base/                        (plain manifest base — 6 apps + frontend)
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/
│   ├── apply.sh                     (mode-aware: helm or kustomize)
│   ├── teardown.sh                  (symmetric teardown + --purge)
│   ├── verify.sh                    (~70 checks)
│   └── build-images.sh              (6 services + frontend with VITE_*)
└── README.md                        (this file)
```

---

## What is *not* in Stage 5

These are reserved for later stages:

- **Observability** (Prometheus, Grafana, OpenTelemetry) — Stage 6
- **Auto-scaling** (HPA, VPA) and Redis caching — Stage 7
- **RBAC hardening, SecurityContext, OPA, Vault** — Stage 8
- **Cloud provisioning** (EKS/GKE via Terraform) — Stage 9
- **Service mesh, progressive delivery, chaos testing** — Stage 10
- **Custom operator, k3s, KEDA** — Stage 11

---

## What's Next

Stage 6 adds **observability** — Prometheus scrapes `/metrics` from each
service, Grafana dashboards visualise booking latency, and OpenTelemetry
propagates trace IDs across service boundaries.
