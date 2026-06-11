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
| **ArgoCD version** | v2.13.x (matches `argocd` CLI in `devbox.json`) |
| **Install pattern** | `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml` — **or** use the bundled offline install for air-gapped clusters |
| **Delivery model** | Three `Application` CRs, one per environment, all sourced from `stages/stage5/helm/apollo11/` |
| **Scope** | This module installs ArgoCD into the cluster, then registers the three Apollo Applications. It does **not** re-install the workloads — that's `stages/stage5/scripts/apply.sh`'s job. |
| **Verify target** | ~25 checks: ArgoCD pods Healthy, 3 Applications Synced+Healthy, AppProject exists with restricted scope, repo creds working, manifests rendered correctly per env |

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
                                          │  apollo-airlines │
                                          │  -apps / -ui     │
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

### Data plane (lives in `apollo-airlines-apps` / `apollo-airlines-ui`)

The same workloads Stage 4 / Stage 5 already defined. ArgoCD does **not**
create or own these namespaces directly — the chart does (via its bundled
`namespace.yaml` template). ArgoCD just *manages* what's in them.

### Application CRs (one per env)

| Name | Source path | Values file | Sync policy | Notes |
|---|---|---|---|---|
| `apollo11-dev` | `stages/stage5/helm/apollo11` | `values-dev.yaml` | automated + prune + selfHeal | Fast iteration |
| `apollo11-staging` | same | `values-staging.yaml` | automated + prune + selfHeal | Pre-prod mirror |
| `apollo11-prod` | same | `values-prod.yaml` | **manual** | Production — human gates sync |

All three Applications live in the **`apollo-airlines` ArgoCD namespace**
(not the `argocd` system namespace) and are scoped by an `AppProject` of
the same name. This is best practice: ArgoCD system resources stay in
`argocd`, your tenant resources in their own namespace.

### AppProject

`projects/project.yaml` defines `apollo-airlines` with:

- **Source repos:** only this repo (or a future mirror).
- **Destinations:** only `apollo-airlines-apps` and `apollo-airlines-ui`.
- **Cluster resource whitelist:** none (no cluster-scoped resources).
- **Namespace resource whitelist:** everything in those two namespaces.

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
│   └── argocd-install.yaml            (offline-friendly ArgoCD v2.13.2 manifest)
├── projects/
│   └── project.yaml                   (AppProject: apollo-airlines)
├── applications/
│   ├── dev.yaml                       (Application: apollo11-dev)
│   ├── staging.yaml                   (Application: apollo11-staging)
│   └── prod.yaml                      (Application: apollo11-prod, manual sync)
└── scripts/
    ├── bootstrap.sh                   (install ArgoCD + project + 3 apps, idempotent)
    ├── verify.sh                      (~25 checks: pods, applications, project, health)
    └── teardown.sh                    (remove apps + project, optional --full uninstall)
```

> The `bundles/argocd-install.yaml` is intentionally **not** committed by
> default — see "Offline install" below. Run `./install.sh` once with
> internet access to fetch it, or use the live manifest URL.

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
3. **`argocd` CLI** (in `devbox.json`, install with `devbox install` or
   `brew install argocd`).
4. **`helm` 3.14+** (already in devbox).
5. **The repo cloned locally** — the `repoServer` is configured to use a
   `helm` type source pointing at a local path, which only works if ArgoCD
   is told the path. For dev, we use the `directory` source type pointing
   at the chart's parent dir. **For prod / a real cluster, change the
   `repoURL` to `https://github.com/<owner>/<repo>` and push the repo.**

---

## Quickstart (TL;DR)

```bash
cd stages/stage5/argocd

# 1. Install ArgoCD into the cluster
bash install.sh

# 2. Register the AppProject + 3 Applications
bash scripts/bootstrap.sh

# 3. Watch the magic
argocd app list -n apollo-airlines
argocd app sync apollo11-dev --grpc-web    # force first sync (or wait for auto)

# 4. Verify
bash scripts/verify.sh

# 5. Open the UI (port-forward, default password: see install.sh output)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
open http://localhost:8080
```

Full walkthrough — including the "Application is OutOfSync because ArgoCD
doesn't know about the existing helm release" gotcha and how to fix it —
is in `DEMO.md`.
