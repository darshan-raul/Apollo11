---
title: "Stage 5 — ArgoCD GitOps Module"
description: "Declarative GitOps delivery of the Stage 5 Helm chart. ArgoCD watches the repo and reconciles dev / staging / prod Applications from the same chart, each pinned to its own values file."
---

# Stage 5 — ArgoCD GitOps Module

**Goal:** Make Apollo Airlines **declaratively deployed**. ArgoCD watches this
repo, syncs the Stage 5 Helm chart into three environments (dev / staging /
prod), and continuously reconciles drift.

| | |
|---|---|
| **New concept** | GitOps, AppProject, Application, sync policy, prune, self-heal, sync waves, manifests rendered with Kustomize side-by-side Helm |
| **Argo CD version** | v3.5.1, pinned and vendored |
| **Install pattern** | `bash install.sh --offline` applies the official manifest server-side with force-conflicts |
| **Delivery model** | Three `Application` CRs, one per environment, all sourced from `stages/stage5/helm/apollo11/` |
| **Scope** | Installs Argo CD, a shared Gateway/MetalLB platform, and three namespace-isolated Applications |
| **Verify target** | 74 live checks, including a real self-heal test |

---

## Why GitOps now?

Stage 5's existing `apply.sh` is **imperative** — you `helm install` and the
cluster holds the state. ArgoCD flips this:

```
  ┌────────────────────┐    git pull    ┌──────────────────┐
  │  this repo (Git)   │ ──────────────▶│   ArgoCD server  │
  │  stages/stage5/    │                │  (in-cluster)    │
  │  helm/apollo11/    │                └────────┬─────────┘
  └────────────────────┘                           │
                                          sync + reconcile
                                                   │
                                                   ▼
                                          ┌──────────────────┐
                                          │  target cluster  │
                                          │  dev/stage/prod  │
                                          │  isolated pairs  │
                                          └──────────────────┘
```

- **Git is the source of truth.** `kubectl apply` is a footgun; `git push` is
  a pull request.
- **Drift detection.** If someone runs `kubectl edit deployment booking`
  on Friday night, ArgoCD reverts it within 3 minutes (default sync window).
- **Per-env promotion.** Same chart, three `values-{env}.yaml`, three
  `Application` CRs. No "did we install the right values file?" guesswork.
- **Auditable history.** `argocd app history apollo11-prod` shows every
  sync, who triggered it, and the diff.

---

## Architecture

### Control plane (lives in `argocd` namespace)

| Component | What it does |
|---|---|
| `argocd-server` | Web UI + gRPC API. Default: `ClusterIP` Service. We expose it via `kubectl port-forward` for local dev (see `bootstrap.sh`). |
| `argocd-repo-server` | Clones the Git repo, renders Helm/Kustomize templates, returns manifests to the controller. |
| `argocd-application-controller` | Watches `Application` CRs, computes diff, applies. |
| `argocd-applicationset-controller` | (Optional, not enabled by default in this module — would be needed for cluster-sharded deploys later.) |
| `argocd-redis` | Caches rendered manifests. |
| `argocd-dex-server` | (Disabled by default; we use local users for dev.) |

### Data plane (six isolated namespaces)

Dev, staging, and prod each receive an `-apps` and `-ui` namespace. The
platform manifest creates those namespaces once; each Application can manage
only its own pair. A shared GatewayClass and MetalLB pool stay outside tenant
ownership.

### Application CRs (one per env)

| Name | Source path | Values file | Sync policy | Notes |
|---|---|---|---|---|
| `apollo11-dev` | `stages/stage5/helm/apollo11` | `values-dev.yaml` | automated + prune + selfHeal | Fast iteration |
| `apollo11-staging` | same | `values-staging.yaml` | automated + prune + selfHeal | Pre-prod mirror |
| `apollo11-prod` | same | `values-prod.yaml` | **manual** | Production — human gates sync |

All three Applications and their AppProject live in Argo CD's standard
`argocd` namespace. This avoids requiring the optional
"Applications in any namespace" controller configuration.

### AppProject

`projects/project.yaml` defines `apollo-airlines` with:

- **Source repos:** only this repo (or a future mirror).
- **Destinations:** only the six dev/staging/prod namespace targets.
- **Cluster resource whitelist:** none (no cluster-scoped resources).
- **Namespace resource whitelist:** everything inside those six namespaces.

This is a soft-isolation pattern — the same cluster can host multiple
projects (e.g. `apollo-airlines`, `data-platform`, `monitoring`) without
cross-contamination.

---

## Files

```
stages/stage5/argocd/
├── README.md                          (this file — concepts + architecture)
├── DEMO.md                            (101 step-by-step walkthrough)
├── install.sh                         (one-shot ArgoCD install into the cluster)
├── uninstall.sh                       (one-shot ArgoCD removal)
├── bundles/
│   └── argocd-install.yaml            (offline-friendly ArgoCD v3.5.1 manifest)
├── platform/
│   └── platform.yaml                  (six namespaces + shared GatewayClass/pool)
├── projects/
│   └── project.yaml                   (AppProject: apollo-airlines)
├── applications/
│   ├── dev.yaml                       (Application: apollo11-dev)
│   ├── staging.yaml                   (Application: apollo11-staging)
│   └── prod.yaml                      (Application: apollo11-prod, manual sync)
└── scripts/
    ├── bootstrap.sh                   (install ArgoCD + project + 3 apps, idempotent)
    ├── validate.sh                    (offline static isolation/render gate)
    ├── verify.sh                      (74 checks: control plane, apps, workloads, self-heal)
    └── teardown.sh                    (remove apps + project, optional --full uninstall)
```

> `bundles/argocd-install.yaml` is the vendored official v3.5.1 non-HA
> manifest (34,050 lines). Use `--fetch-bundle --version ...` only when
> deliberately upgrading the pin.

---

## What this module does NOT do

- **Does not provision clusters.** Run `kind create cluster` (or EKS/GKE) first.
- **Does not install Apollo workloads.** `bootstrap.sh` registers the
  Applications; on the first sync they call `helm template` against the
  chart and apply. If you want to pre-seed, run `stages/stage5/scripts/apply.sh`
  first, then let ArgoCD adopt the resources (set `prune: false` until you're
  sure — see "Adoption gotcha" in DEMO.md).
- **Does not configure SSO / OIDC.** Local users only. Add `argocd-cm` +
  `argocd-rbac-cm` patches later.
- **Does not set up notifications.** The Slack/PagerDuty webhook CRs come
  in Stage 6 (Mission Ops).
- **Does not enable HA.** Single-replica Redis + application-controller is
  fine for a kind cluster. Production HA is a Stage 9+ concern.

---

## Prerequisites

1. **A running cluster** — `kind create cluster --name apollo11` or any
   k8s 1.29+ cluster.
2. **`kubectl`** configured to talk to it (`kubectl cluster-info` works).
3. **`helm` 3.14+** for the static validation gate.
4. **A reachable Git repo.** Defaults point to the canonical GitHub repo;
   `bootstrap.sh --repo-url URL` supports forks and local test fixtures.
5. **Images.** CI publishes GHCR images; for a kind-only exercise preload
   images and pass `--image-repository apollo11`.

---

## Quickstart (TL;DR)

```bash
cd stages/stage5/argocd

# 1. Install Argo CD from the vendored official bundle
bash install.sh --offline

# 2. Register the AppProject + 3 Applications
bash scripts/bootstrap.sh --sync

# 3. Watch the magic
kubectl get applications -n argocd

# 4. Verify
bash scripts/verify.sh

# 5. Open the UI (install.sh prints a command to retrieve the credential)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
open https://localhost:8080
```

Full walkthrough — including the "Application is OutOfSync because ArgoCD
doesn't know about the existing helm release" gotcha and how to fix it —
is in `DEMO.md`.
