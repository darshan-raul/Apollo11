---
title: "Stage 5: Payload Integration — Helm + Kustomize + GitHub Actions"
description: "Package the Stage 4 (probes + QoS + graceful SIGTERM) workloads as a versioned Helm chart for the local learning environment with Kustomize overlays for dev/staging/prod and a CI workflow that builds + pushes images to GHCR."
---

> **Current verification status:** the context, TLS, and contract fixes in this
> working tree require a fresh runtime lifecycle. Counts below record earlier
> revisions; use the current verifier's summary rather than expecting those totals.

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
| **Verify target** | **153 Helm checks / 142 Kustomize checks / 74 Argo CD checks** |

**Verified 2026-08-22 on a fresh three-node kind v1.35.0 cluster:** Helm/dev
153/153, Kustomize/dev 142/142, and Argo CD v3.5.1 74/74 (including real
self-heal). Each path completed a full purge with no namespace, PVC, or related
CRD residue. The active root GitHub Actions workflow is statically validated;
its hosted run and first GHCR release publish occur on the next push/tag.

---

## What changed vs Stage 4

### 1. Helm chart (production deployment path)

The chart at `stages/stage5/helm/apollo11/` is a single source of truth
for the cluster. `helm install` provisions everything:

```
helm/apollo11/
├── Chart.yaml                          (metadata: name, version 1.0.0)
├── values.yaml                         (configurable defaults)
├── values-dev.yaml                     (env-specific: 1 replica, :latest tag, no PDBs)
├── values-staging.yaml                 (env-specific: 2 replicas, :latest tag, no PDBs)
├── values-prod.yaml                    (env-specific: 3 replicas, :v1.0.0 tag, full PDBs, GHCR pull)
├── bundles/
│   ├── envoy-gateway-install.yaml      (v1.5.0, 2.9MB — offline-friendly)
│   └── metallb-native.yaml             (v0.14.5, 67KB — offline-friendly)
└── templates/
    ├── _helpers.tpl                    (label, selector, name helpers)
    ├── config/
    │   ├── serviceaccount.yaml         (13 SAs; apply/bootstrap owns namespaces)
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
| `image.repository` | `apollo11` | Override registry (e.g. `ghcr.io/darshan-raul/apollo11`) |
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
├── base/
│   ├── kustomization.yaml
│   └── generated.yaml   # complete committed 61-resource plain base
├── dev/                 # 1 replica, tag=latest
├── staging/             # 2 replicas, tag=latest
└── prod/                # 3 replicas, tag=v1.0.0, +PDBs
```

The Kustomize base is a complete committed plain-manifest render of the
verified chart: configuration, 13 ServiceAccounts, four StatefulSets, all
Deployments/Services, seed Jobs, Gateway, routes, and MetalLB configuration.
The runtime path never calls `helm template`; it installs only the prerequisite
controller bundles before applying the selected overlay.

### 3. GitHub Actions CI

`.github/workflows/main.yml` (replaces the stock "Hello, world" stub):

1. **Lint job** — `helm lint`, `helm template` smoke render, `kubectl kustomize build` for all 3 overlays, `shellcheck` on the scripts.
2. **Build job** — Matrix build of all 6 service images using `docker/build-push-action@v6` with GHA cache. Frontend gets `VITE_*` URLs from `values.yaml` injected as build args.
3. **Push job** — Only on `main` push or `v*` tag, push lowercase GHCR paths
   with immutable `:sha-*`, `:latest` on main, and the actual `:v*` release tag.

No deploy step — ArgoCD (separate tooling, see section 4 below) handles deploys from GHCR.

### 4. ArgoCD GitOps module

`argocd/` (see `argocd/README.md` for the full architecture and
`argocd/DEMO.md` for the step-by-step walkthrough):

1. **Platform layer** — one shared GatewayClass/MetalLB pool plus dedicated
   dev, staging, and prod namespace pairs.
2. **AppProject** `apollo-airlines` — security boundary restricting tenant
   Applications to those six namespaces and denying cluster-scoped resources.
3. **Three Applications** — `apollo11-dev` (automated sync), `apollo11-staging`
   (automated), `apollo11-prod` (manual sync, `v1.0.0` image).
4. **Install** — vendored Argo CD v3.5.1 via `bash argocd/install.sh --offline`.
5. **Bootstrap** — `bash argocd/scripts/bootstrap.sh --sync` registers
   the project + apps and force-syncs dev + staging.
6. **Verify** — `bash argocd/scripts/verify.sh` runs 74 GitOps checks.
7. **Teardown** — `bash argocd/scripts/teardown.sh [--full|--purge]`.

The ArgoCD module is **optional** — `apply.sh` + the CI workflow alone
are a complete Stage 5. ArgoCD is the production delivery layer for
clusters that have one.

---

## Environment Comparison

| Setting | Dev | Staging | Prod |
|---|---|---|---|
| **Deployment path** | Kustomize overlay (`apply.sh --mode kustomize --env dev`) | Kustomize overlay (`--env staging`) | Helm chart (recommended) or Kustomize (`--env prod`) |
| **Replicas per app** | 1 | 2 | 3 |
| **Image tag** | `:latest` | `:latest` | `:v1.0.0` (pinned) |
| **PodDisruptionBudgets** | No | No | Yes (`minAvailable: 2`) |
| **Access stack** | Yes (via chart components during `apply.sh`) | Yes | Yes |
| **StatefulSets** | Yes | Yes | Yes |
| **Cost** | Lowest | Medium | Highest |

**Dev** is the cheapest cluster — 1 replica each, latest image tag, no PDBs.
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
bash scripts/apply.sh --env dev       # values-dev.yaml — 1 replica, :latest tag
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

# Dev overlay (1 replica, :latest tag)
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

### ArgoCD (GitOps, optional)

```bash
cd stages/stage5/argocd

# One-time: install ArgoCD into the cluster
bash install.sh

# Register the project + 3 applications, force-sync dev + staging
bash scripts/bootstrap.sh --sync

# Verify (74 GitOps checks)
bash scripts/verify.sh

# Teardown
bash scripts/teardown.sh                # remove 3 applications
bash scripts/teardown.sh --full         # also remove ArgoCD system
bash scripts/teardown.sh --purge        # also remove cluster-scoped CRDs
```

See `argocd/DEMO.md` for the 101 walkthrough.

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
│   └── templates/                   (19 templates)
├── overlays/                        # Kustomize overlays
│   ├── base/                        (complete 61-resource plain manifest base)
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/
│   ├── apply.sh                     (mode-aware: helm or kustomize)
│   ├── teardown.sh                  (symmetric teardown + --purge)
│   ├── verify.sh                    (153 Helm / 142 Kustomize checks)
│   └── build-images.sh              (6 services + frontend with VITE_*)
├── argocd/                          # GitOps delivery layer (optional)
│   ├── README.md                    (concepts + architecture)
│   ├── ARGOCD.md                    (complete ArgoCD reference guide)
│   ├── DEMO.md                      (101 walkthrough)
│   ├── install.sh                   (vendored Argo CD v3.5.1 install)
│   ├── uninstall.sh                 (ArgoCD removal)
│   ├── bundles/                     (offline install manifest)
│   ├── platform/                    (shared cluster resources + six namespaces)
│   ├── projects/
│   │   └── project.yaml             (AppProject: apollo-airlines)
│   ├── applications/
│   │   ├── dev.yaml                 (auto-sync, values-dev.yaml)
│   │   ├── staging.yaml             (auto-sync, values-staging.yaml)
│   │   └── prod.yaml                (manual sync, values-prod.yaml, pinned v1.0.0)
│   └── scripts/
│       ├── bootstrap.sh             (install + project + 3 apps, idempotent)
│       ├── validate.sh              (static environment-isolation gate)
│       ├── verify.sh                (74 live GitOps checks)
│       └── teardown.sh              (apps-only, --full, --purge)
├── ../../.github/workflows/main.yml # active CI: lint + matrix build + GHCR push
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

## Local HTTPS and certificate ownership

The canonical Gateway offers HTTP on port 80 and HTTPS on port 443. Frontend
API URLs are now baked as HTTPS; rebuild images before switching snapshots.
The certificate Secret is generated at installation time and preserved across
reapplication. It is not part of Helm release ownership or the Kustomize base.
Use `bash scripts/generate-certs.sh --rotate` to renew it deliberately.

Export `KUBE_CONTEXT=kind-apollo11` (or `kind-apollo11-dev`) before using the
scripts. For a manual Helm/Kustomize install, create both application namespaces
and run the certificate generator before submitting Gateway resources. Argo CD
bootstrap prepares separate certificates in each tenant's namespaces.

Extract the public certificate, then check the actual DNS hostname and trust:

```bash
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get secret apollo-edge-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/apollo-ca.crt
gateway_ip=$(kubectl --context "$KUBE_CONTEXT" -n envoy-gateway-system get service \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl --cacert /tmp/apollo-ca.crt --resolve "identity.apollo.local:443:$gateway_ip" \
  https://identity.apollo.local/healthz
```

Add the Gateway address and all five hostnames to local name resolution before
using the browser. Trust the local certificate using your browser/OS's local
certificate facility, then open `https://frontend.apollo.local`. Verify login,
flight search, and a reversible booking in the browser's Network panel: all API
requests must use HTTPS. A successful HTML response alone does not establish
that behavior. `curl -k` skips trust verification and is only a diagnostic.

Delete the apps-namespace certificate to break the HTTPS listener. HTTP should
remain available. Re-run the certificate generator and require a trusted HTTPS
response plus login/search recovery. If the old certificate was deleted,
extract the replacement and update local trust. Teardown removes the runtime
certificate when it deletes the owned namespace.
