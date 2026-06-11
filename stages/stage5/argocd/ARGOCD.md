---
title: "The Complete ArgoCD Guide"
description: "Everything you need to understand, install, configure, operate, and troubleshoot ArgoCD — from the core reconciliation model to multi-cluster GitOps, AppSets, notifications, and security hardening."
---

# The Complete ArgoCD Guide

**Audience:** anyone who wants to actually understand ArgoCD — not just
"apply this manifest and pray." The Apollo11 project uses ArgoCD in
`stages/stage5/argocd/`, but the material here applies to any cluster.

**Length:** long. This is meant to be a reference, not a quickstart. For
the project-specific walkthrough, see `DEMO.md`.

---

## Table of contents

1. [What ArgoCD is (and isn't)](#1-what-argocd-is-and-isnt)
2. [The reconciliation model](#2-the-reconciliation-model)
3. [Architecture: every component explained](#3-architecture-every-component-explained)
4. [Core CRDs: AppProject, Application, ApplicationSet](#4-core-crds-appproject-application-applicationset)
5. [Source types and rendering](#5-source-types-and-rendering)
6. [Sync policies in depth](#6-sync-policies-in-depth)
7. [Drift detection and self-heal](#7-drift-detection-and-self-heal)
8. [Hooks, waves, and phased rollouts](#8-hooks-waves-and-phased-rollouts)
9. [The sync window contract](#9-the-sync-window-contract)
10. [Multi-tenancy and security boundaries](#10-multi-tenancy-and-security-boundaries)
11. [The CLI: the API the UI is built on](#11-the-cli-the-api-the-ui-is-built-on)
12. [The UI: navigating efficiently](#12-the-ui-navigating-efficiently)
13. [Notifications: alerting on sync events](#13-notifications-alerting-on-sync-events)
14. [Single Sign-On (SSO)](#14-single-sign-on-sso)
15. [High availability and scaling](#15-high-availability-and-scaling)
16. [Backup and disaster recovery](#16-backup-and-disaster-recovery)
17. [ApplicationSets: templated fan-out](#17-applicationsets-templated-fan-out)
18. [Multi-cluster GitOps](#18-multi-cluster-gitops)
19. [Progressive delivery with Argo Rollouts](#19-progressive-delivery-with-argo-rollouts)
20. [Performance tuning and resource limits](#20-performance-tuning-and-resource-limits)
21. [Common failure modes and debugging](#21-common-failure-modes-and-debugging)
22. [Anti-patterns to avoid](#22-anti-patterns-to-avoid)
23. [Glossary](#23-glossary)

---

## 1. What ArgoCD is (and isn't)

### The one-sentence definition

ArgoCD is a **declarative, GitOps continuous delivery tool for Kubernetes**
that keeps the live cluster state converged with the desired state defined
in a Git repository.

### The five properties that flow from that one sentence

| Property | What it means | Why it matters |
|---|---|---|
| **Declarative** | You describe the end state, not the steps to reach it. The Application CR *is* the spec. | No imperative scripts; the controller figures out how to get there. |
| **GitOps** | Git is the source of truth. The cluster state is a *function* of Git. | Every change has a commit, an author, a PR, an approval. Audit trail is free. |
| **Continuous delivery** | The tool is running all the time, not invoked per-deploy. | A push to main → cluster changes within seconds. No "did someone run the deploy script?" |
| **For Kubernetes** | ArgoCD speaks the k8s API natively. It applies manifests, watches resources, computes diffs in-tree. | No agent on every node; no SSH; no daemon. Just a controller in a namespace. |
| **Reconciliation loop** | The controller runs `desired ← live; live ← desired` continuously. | The cluster heals itself. Drift is a transient bug, not a persistent state. |

### What ArgoCD is NOT

- **It is not a CI tool.** It does not build images, run tests, or decide
  when to release. That's Jenkins / GitHub Actions / Tekton / etc.
  ArgoCD picks up *what* to deploy; CI decides *whether* it's deployable.

- **It is not a service mesh.** It doesn't route traffic, enforce
  policies between services, or inject sidecars. That's Linkerd /
  Istio / Consul.

- **It is not a deployment system like Helm.** ArgoCD *uses* Helm
  internally (the `helm` source type invokes `helm template`), but
  ArgoCD owns the *apply* step. After the first sync, ArgoCD does not
  need Helm to be installed. (This is a common misconception.)

- **It is not a single-cluster tool, despite the default install.** A
  single ArgoCD can manage many clusters; a single cluster can be
  managed by many ArgoCDs. The Apollo11 setup uses the hub-and-spoke
  pattern with one in-cluster ArgoCD.

### The two-line mental model

```
Git repo  →  ArgoCD (diff, render, plan)  →  Kubernetes API (apply, watch, converge)
```

That's it. The rest of this guide is how the middle box works.

---

## 2. The reconciliation model

This is the single most important section. If you understand this, the
rest is implementation details.

### The desired state function

ArgoCD computes a **desired state** for each Application by:

1. Reading the source repo at a given revision
2. Rendering the manifests (Helm, Kustomize, plain YAML, or a custom tool)
3. The output is a set of *desired* Kubernetes objects

The **live state** is whatever the cluster's API server reports for the
destination namespace.

The **controller** runs a loop:

```
loop:
  desired = read_source().render()
  live    = api_server.list(destination)
  diff    = compute_diff(desired, live)
  if diff.is_empty():
    status = "Synced"
  else:
    status = "OutOfSync"
  if syncPolicy.automated and diff.is_significant():
    apply(diff.to_apply())
    prune(diff.to_prune())
  if syncPolicy.automated.selfHeal:
    revert any drift not in desired
```

This is **eventually consistent**. ArgoCD is not a transactional system;
it converges over time, not in a single moment.

### The three states of an Application

ArgoCD reports two orthogonal statuses:

| sync.status | health.status | What it means |
|---|---|---|
| `Synced` | `Healthy` | Cluster matches repo. Everything works. |
| `Synced` | `Progressing` | Cluster matches repo, but a Deployment is rolling out. |
| `Synced` | `Degraded` | Cluster matches repo, but a workload is failing (e.g. CrashLoopBackOff). |
| `OutOfSync` | `Healthy` | Cluster has drifted from repo. Will be reverted if `selfHeal=true`. |
| `OutOfSync` | `Degraded` | Cluster has drifted AND something is broken. Fix the source. |
| `Unknown` | `Unknown` | ArgoCD can't reach the API server, or the source repo. |

The first thing to check when an Application is misbehaving: **are
`sync` and `health` independent?** Yes. They mean different things. A
"Healthy" app can be out of sync (about to be healed, or just-not-yet
caught). An "OutOfSync" app can be Healthy (a manual edit was made and
is waiting for the next selfHeal pass).

### Why this model is robust

- **Idempotent.** Re-applying the same desired state is a no-op.
- **Convergent.** Drift is a state, not a mode. The controller always
  pulls the cluster back to the desired state.
- **Observable.** Diff is computed every reconcile (default 3 minutes).
  You can see what changed, when, and by whom.
- **Recoverable.** The cluster state is a function of (repo, revision,
  config). If a node dies, the controller re-creates the workloads
  from Git. No "but the deploy script didn't run after the failover."

### Why this model is *also* dangerous

- **Self-heal is a footgun in dev.** You `kubectl edit` to debug, walk
  away, and 3 minutes later your edit is gone. ArgoCD will not tell you
  it reverted; you have to watch `argocd app diff` to see drift.
- **Prune is a footgun in shared environments.** A bad commit that
  removes a `volumeClaimTemplate` from a chart will *delete* your data
  if `prune: true`. Always use `prunePropagationPolicy: foreground` and
  review before sync.
- **No transactional boundary.** A sync that updates 50 objects
  applies them one by one. If the 25th fails, the first 24 are already
  applied. There is no "all or nothing."

---

## 3. Architecture: every component explained

A full ArgoCD install has 5+ Deployments/StatefulSets. Each does one
job. Understanding them is essential for debugging.

```
                  ┌───────────────────────────────────────────────┐
                  │  argocd-server (Deployment)                    │
   argocd CLI ───▶│  - gRPC API (port 443)                        │
   Web UI    ───▶│  - OIDC / SSO                                  │
                  │  - WebSocket for live sync status              │
                  └────────────────┬──────────────────────────────┘
                                   │
                                   ▼
                  ┌───────────────────────────────────────────────┐
                  │  argocd-application-controller (StatefulSet)   │
                  │  - Watches Application CRs                     │
                  │  - Computes desired state via repoServer       │
                  │  - Applies diffs to the API server             │
                  │  - Updates Application status                  │
                  └────────────────┬──────────────────────────────┘
                                   │
                                   ▼
                  ┌───────────────────────────────────────────────┐
                  │  argocd-repo-server (Deployment)               │
                  │  - Clones the source repo                      │
                  │  - Runs helm/kustomize/etc.                    │
                  │  - Returns rendered manifests                  │
                  │  - Caches results in Redis                     │
                  └────────────────┬──────────────────────────────┘
                                   │
                                   ▼
                  ┌───────────────────────────────────────────────┐
                  │  argocd-redis (Deployment)                     │
                  │  - Cache for rendered manifests               │
                  │  - Cache for repo clones                      │
                  │  - Cache for diff results                     │
                  │  NOT a stateful store — losing it is fine      │
                  └───────────────────────────────────────────────┘
        ┌────────────────┐
        │  argocd-dex    │  (optional, default install has it)
        │  - SSO bridge  │
        │  - Pluggable connectors (GitHub, GitLab, OIDC, LDAP)
        └────────────────┘
        ┌─────────────────────┐
        │  argocd-notifications│ (separate chart, not in default)
        │  - Send Slack / PagerDuty / webhook on sync events
        └─────────────────────┘
        ┌─────────────────────┐
        │  argocd-applicationset-controller│ (separate chart)
        │  - Renders N Applications from a single template
        └─────────────────────┘
```

### argocd-server

The user-facing component. Speaks gRPC (port 443 inside the cluster) and
serves the web UI. Does not apply manifests itself — it forwards API
requests to the application-controller.

**Key config:**
- `--disable-auth` — DEV ONLY. Never set in prod.
- `--insecure` — skip TLS (you'll terminate at an ingress with a real cert).
- `--dex-server` — point to the dex Service for SSO.

**Pod-local state:** none. Stateless. Scale to N replicas for HA.

### argocd-application-controller

The brain. A StatefulSet (not a Deployment) because it uses a
`volumeClaimTemplate` for its leader-election lock — even though it
could be a Deployment in 2.10+, the StatefulSet is the default for
backwards-compat reasons.

**Key config:**
- `--status-processors` (default 20) — number of concurrent
  reconciliation goroutines. Tune up for thousands of apps.
- `--operation-processors` (default 10) — number of concurrent
  sync operations. Sync is heavier than reconcile.
- `--self-heal-timeout` (default 5s) — minimum time between
  selfHeal syncs for the same app.
- `--repo-server-timeout` (default 60s) — how long to wait for
  repoServer to render.

**Pod-local state:** the lease (leader-election) and a local cache of
Application status. Both are recoverable.

### argocd-repo-server

The workhorse. Per Application, every 3 minutes (or whatever the
Application's `syncPolicy.retry` says), it:

1. Checks out the source repo at `targetRevision` (or hits the
   in-memory cache).
2. Runs the rendering tool (Helm, Kustomize, etc.) with the right
   parameters.
3. Returns the rendered manifests to the application-controller.

**Key config:**
- `--repo-cache-expiration` (default 24h) — how long to cache
  rendered manifests.
- `--max-connections` — limit concurrent repoServer calls (default
  no limit, can OOM under load).
- `--disable-helm` — if you don't use Helm.

**Pod-local state:** none. Stateless. But it's CPU- and memory-heavy
during render. Scale horizontally.

**Custom tooling:** ArgoCD supports custom config management tools via
the `argocd-cm` ConfigMap. You can plug in `cue`, `jsonnet`, `sops`,
etc. by adding an entry. The contract is: "given a directory, return
rendered YAML."

### argocd-redis

Cache. Single replica by default. In a production HA install, run it
as a Sentinel cluster or use a managed Redis. Losing Redis does *not*
lose cluster state — ArgoCD will re-render everything, but the API
will be slow for a few minutes.

### argocd-dex (optional)

OIDC bridge. Most installs enable it for SSO via GitHub, GitLab,
Google, LDAP, etc. You can disable it with `--disable-dex` and use
local users in `argocd-cm` for dev clusters.

### Application-level controllers (separate)

`argocd-applicationset-controller` and `argocd-notifications-controller`
are separate Helm charts. The default `install.yaml` does NOT include
them. Install them when you need:
- `ApplicationSet` CRs (multi-cluster, multi-env fan-out)
- Slack/PagerDuty notifications on sync events

---

## 4. Core CRDs: AppProject, Application, ApplicationSet

### AppProject — the security boundary

A logical grouping of Applications with shared constraints. **Every
Application must reference an AppProject.** Without one, the controller
rejects the Application.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: apollo-airlines
  namespace: apollo-airlines
spec:
  sourceRepos:        # which git repos this project can pull from
    - 'https://github.com/darshan/Apollo11'
  destinations:       # which clusters + namespaces apps can deploy to
    - server: https://kubernetes.default.svc
      namespace: apollo-airlines-apps
    - server: https://kubernetes.default.svc
      namespace: apollo-airlines-ui
  clusterResourceWhitelist: []   # no cluster-scoped
  namespaceResourceWhitelist:    # everything in those namespaces
    - group: '*'
      kind: '*'
  orphanedResources:             # monitor for resources no app owns
    warn: true
    ignore: []
  roles: []                      # RBAC
```

**Key gotchas:**

- `sourceRepos` uses simple string match, not regex. `'*'` allows
  everything (fine for dev, dangerous in prod).
- `destinations.server` must match the **server URL in the
  Application**, not just the in-cluster service URL. For multi-cluster,
  Applications must reference each remote cluster by its exact
  registration name.
- `clusterResourceWhitelist` defaults to **denying** all cluster-scoped
  resources. To allow specific ones, you must enumerate.
- `namespaceResourceWhitelist` defaults to **allowing** all namespaced
  resources. To lock down, enumerate explicitly.
- The AppProject's `metadata.namespace` is where the project lives. The
  Applications in the project can be in a *different* namespace, but
  they must reference the project by `<namespace>/<name>`.

### Application — the deployment contract

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apollo11-dev
  namespace: apollo-airlines
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # delete resources on app delete
spec:
  project: apollo-airlines                     # MUST match an AppProject
  source:
    repoURL: https://github.com/darshan/Apollo11
    targetRevision: HEAD
    path: stages/stage5/helm/apollo11
    helm:
      valueFiles: [values-dev.yaml]
      parameters:
        - name: image.tag
          value: dev
  destination:
    server: https://kubernetes.default.svc
    namespace: apollo-airlines-apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: '*'
      kind: 'Pod'
      jqPathExpressions:
        - '.spec.containers[].resources'
```

**Lifecycle of an Application CR:**

1. **Created** — `kubectl apply -f` or `argocd app create`. The
   controller picks it up on the next reconcile (≤3s).
2. **Reconciling** — controller calls repoServer, gets manifests,
   computes diff, updates status.
3. **Synced/OutOfSync** — based on diff result.
4. **Healthy/Degraded/Progressing** — based on resource health checks.
5. **Operation** — when you trigger a sync, the Application gets a
   `status.operation` field that tracks progress.
6. **Deleted** — if `resources-finalizer` is set, ArgoCD prunes the
   managed resources before the CR is removed. Without the finalizer,
   the resources are orphaned and you have to clean them up by hand.

**Finalizer gotcha:** If you delete the CR with `--cascade=false` or
remove the finalizer first, the resources stay. This is sometimes
intentional (forensics) but usually an accident.

### ApplicationSet — the templated fan-out

An `ApplicationSet` is a CR that *generates* Application CRs from a
template + a list of inputs. Inputs can be:
- Git directories (`git` generator)
- Cluster list (`cluster` generator)
- A matrix of two lists (`matrix` generator)
- Output of a plugin (`plugin` generator)

Example: deploy the same chart to 3 clusters × 3 environments = 9
Applications, from a single ApplicationSet.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apollo11
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - list:
              items:
                - cluster: dev-cluster
                  env: dev
                - cluster: staging-cluster
                  env: staging
                - cluster: prod-cluster
                  env: prod
          - list:
              items:
                - repoURL: https://github.com/darshan/Apollo11
                  chartPath: stages/stage5/helm/apollo11
  template:
    metadata:
      name: 'apollo11-{{env}}'
    spec:
      project: apollo-airlines
      source:
        repoURL: '{{repoURL}}'
        path: '{{chartPath}}'
        helm:
          valueFiles: ['values-{{env}}.yaml']
      destination:
        name: '{{cluster}}'
        namespace: apollo-airlines-apps
      syncPolicy:
        automated: { ... }
```

This is the recommended pattern for multi-cluster / multi-env
deployments. Apollo11's `applications/{dev,staging,prod}.yaml` could be
collapsed into a single ApplicationSet — we kept them as three explicit
CRs for clarity in teaching.

---

## 5. Source types and rendering

ArgoCD supports four built-in source types. Each goes through the
repoServer for rendering.

### `directory` — plain manifests

```yaml
source:
  repoURL: https://github.com/darshan/Apollo11
  targetRevision: HEAD
  path: stages/stage5/overlays/base
```

Renders all `*.yaml` in the path. No templating. Use for raw
manifests, Kustomize output, or for Kustomize applied via
`kustomization.yaml` in the directory (ArgoCD will auto-detect).

### `helm` — the most common

```yaml
source:
  repoURL: https://github.com/darshan/Apollo11
  targetRevision: HEAD
  path: stages/stage5/helm/apollo11
  helm:
    valueFiles: [values-prod.yaml, secrets.yaml]
    parameters:
      - name: image.tag
        value: v1.2.3
    releaseName: my-release
    skipCrds: false
    skipTests: true
```

ArgoCD runs `helm template` with the parameters and valueFiles
overridden. The rendered output becomes the desired state.

**Gotchas:**
- `valueFiles` paths are relative to the chart directory.
- `parameters` overrides the same name in values files. Useful for
  per-env tweaks without editing values files.
- `skipCrds: true` is occasionally needed when the CRDs are managed
  by a separate Application.
- Helm hooks (the `helm.sh/hook` annotation) are NOT supported. Use
  ArgoCD's native hook system (see §8).

### `kustomize` — overlay support

```yaml
source:
  repoURL: https://github.com/darshan/Apollo11
  targetRevision: HEAD
  path: stages/stage5/overlays/prod
  kustomize:
    namePrefix: prod-
    images:
      - 'apollo11/booking:v1.2.3'
    commonLabels:
      env: prod
```

ArgoCD runs `kustomize build` with the overrides.

**Gotchas:**
- The Kustomize version bundled with ArgoCD is the one that runs. To
  use a different version (e.g. 5.0 features), set the
  `kustomize.version` field in `argocd-cm` or use the `kustomize`
  field on the Application pointing at a custom binary.
- `images:` overrides are applied last. Useful for tag injection
  without templating the manifest.

### `plugin` — custom tooling

For `cue`, `jsonnet`, `sops`, `helmfile`, or anything else.

```yaml
source:
  repoURL: https://github.com/darshan/Apollo11
  targetRevision: HEAD
  path: stages/stage5/manifests
  plugin:
    name: my-plugin
```

You need a `ConfigManagementPlugin` configured in `argocd-cm`:

```yaml
data:
  configManagementPlugins: |
    - name: my-plugin
      generate:
        command: [sh, -c, "find . -name '*.yaml' | xargs yq"]
```

The plugin receives the source dir as `$ARGOCD_APP_SOURCE_PATH` and
must write rendered manifests to stdout. Used for "we have a custom
templating tool" cases.

### Helm + Kustomize + Plugin: when to use what

| Need | Use |
|---|---|
| Pre-built chart from a Helm registry | `helm` with `chart:` instead of `path:` |
| Per-env value variation | `helm` with `valueFiles:` |
| Image tag injection without templating | `kustomize` with `images:` |
| Patch any field on any resource | `kustomize` with `patches:` |
| Multi-tool pipeline (helm → kustomize → sops) | `plugin` |
| Just raw YAML | `directory` |

---

## 6. Sync policies in depth

### The four sync knobs

```yaml
syncPolicy:
  automated:           # turn on continuous sync
    prune: bool        # delete resources that disappeared from the chart
    selfHeal: bool     # revert out-of-band `kubectl edit` changes
    allowEmpty: bool   # refuse to sync if rendered manifest is empty
  syncOptions:         # behavior modifiers
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - ServerSideApply=true
    - ApplyOutOfSyncOnly=true
    - RespectIgnoreDifferences=true
    - FailOnSharedResource=true
  retry:               # what to do if a sync fails
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
  syncWindows:         # per-app gates
    - kind: deny
      schedule: '0 0 * * 6'
      duration: 4h
      applications: ['apollo11-prod']
```

### When to use which

| Use case | `automated` | `prune` | `selfHeal` | `allowEmpty` |
|---|---|---|---|---|
| Dev cluster, "just sync it" | ✅ | ✅ | ✅ | false |
| Staging, auto-sync but allow manual SRE edits | ✅ | ✅ | false | false |
| Prod with high confidence in Git | ✅ | ✅ | ✅ | false |
| Prod with cautious operators (Apollo11 default) | ❌ (manual) | n/a | n/a | false |
| Shared cluster, no SRE trust | ✅ | false | ✅ | false |

### Sync options explained

- **`CreateNamespace=true`** — auto-create the destination namespace
  if it doesn't exist. Required for greenfield apps, surprising for
  multi-tenant.
- **`PrunePropagationPolicy=foreground`** — when deleting a
  Deployment, wait for its pods to terminate before deleting the
  ReplicaSet. Without this, you can race and leave orphan pods.
- **`PruneLast=true`** — apply new resources BEFORE pruning old ones.
  The default (prune first) can cause a brief outage. `PruneLast`
  guarantees a moment where both exist.
- **`ServerSideApply=true`** — use the k8s 1.16+ Server-Side Apply
  API. **Required** for resources with the
  `clientSideApplySemantics: false` annotation (most CRDs from
  operators). Also required for the 256KB last-applied-config limit.
- **`ApplyOutOfSyncOnly=true`** — only apply the diff between
  desired and live, not the full desired set. Faster, lower risk.
- **`FailOnSharedResource=true`** — refuse to sync if another
  Application already manages a resource. Catches the "two apps
  fighting over the same Deployment" bug.
- **`RespectIgnoreDifferences=true`** — apply the
  `ignoreDifferences` rules when computing the diff. Default is
  to ignore them only in the UI display; this makes them affect
  the actual sync.

### Retry behavior

`retry.limit: 5` means "try 5 times before giving up." `backoff`
controls the spacing. The default is reasonable; the gotcha is
**retry is for the whole sync operation, not per-resource.** A
Deployment that hits a quota error will retry the whole sync,
including the StatefulSet that already succeeded. This is wasteful
but not broken.

For per-resource retries, use ArgoCD's hook system (§8).

---

## 7. Drift detection and self-heal

### How drift is detected

On every reconcile (default 3 minutes for Applications with no
`refreshInterval` override), the application-controller:

1. Calls repoServer for the rendered desired state (cached, fast).
2. Calls the API server for the live state.
3. Computes a structural diff (3-way: desired, live, last-applied).
4. Updates `status.sync.status` to `Synced` or `OutOfSync`.

The diff is **structural**, not text-based. Reordering keys in YAML
does not produce drift. Adding a label that the controller doesn't
care about does not produce drift. (You can customize what "cares
about" means via `ignoreDifferences`.)

### `ignoreDifferences` — the secret to clean diffs

By default, ArgoCD compares every field. But:

- The k8s API server injects default fields (e.g. `serviceAccount: default`).
- Operators inject status fields continuously.
- Probes inject dynamic env vars.

This causes noisy `OutOfSync` for what is actually the same state.
The fix:

```yaml
ignoreDifferences:
  - group: apps
    kind: StatefulSet
    jsonPointers:
      - /spec/template/metadata/annotations
  - group: '*'
    kind: 'Pod'
    jqPathExpressions:
      - '.spec.containers[].resources'
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/service/namespace
```

Three selector types:

| Selector | When to use | Example |
|---|---|---|
| `jsonPointers` | You know the exact JSON path | `/spec/replicas` |
| `jqPathExpressions` | You need array / conditional logic | `.spec.containers[].resources` |
| `managedFieldsManagers` | You want to ignore SSA-added fields | `["kube-controller-manager"]` |

**Gotcha:** `ignoreDifferences` only affects the **diff**, not the
**apply**. If you ignore a field and then change it in Git, ArgoCD
will detect the change in the diff but **not apply it** unless you
also use `RespectIgnoreDifferences=true` in `syncOptions`.

### Self-heal and the human-edit problem

`selfHeal: true` means: if a resource differs from the desired state
and the difference is NOT in `ignoreDifferences`, the controller
will overwrite the live state to match the desired state.

This applies whether the drift came from a Git change (good) or
from `kubectl edit` (potentially bad).

**Best practices:**

- **Dev/staging: selfHeal: true.** Your `kubectl edit` is a
  short-lived experiment; the controller will revert it within
  3 minutes. Don't fight it.
- **Prod: selfHeal: false.** An SRE doing incident response
  may need to scale a Deployment by hand; the controller
  reverting it under their feet is worse than the drift.
- **When selfHeal is on, ALWAYS set `selfHealTimeout` in
  `argocd-cm`.** The default is 5s; bumping to 30s gives SREs
  a window to make an emergency edit and have it stick for the
  duration of the incident.

### The OutOfSync self-test

A good end-to-end smoke test for a healthy ArgoCD setup:

```bash
# 1. Pick an app
APP=apollo11-dev

# 2. Cause a known drift
kubectl scale deployment/booking --replicas=99 -n apollo-airlines-apps

# 3. Wait for selfHeal (default 3 minutes)
argocd app wait $APP --health

# 4. Confirm the cluster reverted
kubectl get deployment/booking -n apollo-airlines-apps \
    -o jsonpath='{.spec.replicas}'
# → 1 (or whatever the chart says)
```

If this test fails, self-heal is broken and you have a serious
operational gap. The verify.sh script in `argocd/scripts/verify.sh`
runs a related test (delete a pod, watch it re-create).

---

## 8. Hooks, waves, and phased rollouts

ArgoCD has its own hook system, separate from Helm hooks. It's how
you run a Job before the Deployment rolls out, or run a database
migration before the new app version starts.

### Hook types

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync          # runs before the main sync
    argocd.argoproj.io/hook: PostSync         # runs after the main sync
    argocd.argoproj.io/hook: SyncFail         # runs if the sync fails
    argocd.argoproj.io/hook: Skip             # never created by sync (manual)
```

A `PreSync` hook is the standard way to do "run the migration Job
first, then roll the Deployment."

### Hook deletion policies

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook-delete-policy: HookSucceeded   # delete when done
    argocd.argoproj.io/hook-delete-policy: HookFailed      # delete on failure
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation  # delete before next sync
```

Common patterns:
- **Migration Job**: `hook: PreSync, hook-delete-policy: HookSucceeded`
- **Smoke test**: `hook: PostSync, hook-delete-policy: HookSucceeded`
- **Notification Job**: `hook: SyncFail, hook-delete-policy: HookFailed`

### Sync waves — ordered rollouts

When you have multiple Applications that depend on each other, you
need them to sync in order. ArgoCD's sync waves handle this:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # negative = before
    argocd.argoproj.io/sync-wave: "0"    # default
    argocd.argoproj.io/sync-wave: "1"    # positive = after
```

Sync order:
1. Wave -10 → -9 → -8 → ... → 0 → 1 → ... → N
2. Within a wave, alphabetical by Application name
3. Hooks of the same wave run in order: PreSync → main → PostSync
4. Each Application waits for the previous wave to complete successfully

A typical stack:

```yaml
# Application 1: infra (wave -1)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  source: { path: chart/infra }

# Application 2: jobs (wave 0)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  source: { path: chart/jobs }

# Application 3: apps (wave 1)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  source: { path: chart/apps }
```

The infra Application syncs first (creating StatefulSets, SAs,
ConfigMaps). Then the jobs Application syncs (running the seed Jobs
against the now-ready DBs). Then the apps Application syncs (rolling
out the Deployments that need the seeded data).

This is the Apollo11 model — three Applications could replace the
single monolithic one, each with a different wave.

### The wave + hook combination

The most powerful pattern:

```yaml
# chart/jobs/templates/seed.yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

A Job that runs only as a PreSync hook, then deletes itself. This is
how you do "idempotent migration" cleanly — re-running the chart
re-runs the hook, the hook does the migration, the hook cleans up.

---

## 9. The sync window contract

A sync window is a time-bounded rule that gates sync operations. Useful
for:
- "Don't auto-sync prod on Friday after 5pm"
- "Don't auto-sync anything during the daily backup at 2am"
- "Allow manual sync anytime, automated only during business hours"

```yaml
spec:
  syncWindows:
    - kind: deny
      schedule: '0 0 * * 6'   # Saturday 00:00 UTC
      duration: 4h             # for 4 hours
      applications:
        - apollo11-prod
      manualSync: true         # manual sync OK during deny window
    - kind: allow
      schedule: '0 9 * * 1-5'  # weekdays 09:00
      duration: 8h             # 09:00-17:00
      applications:
        - apollo11-prod
```

**Important behavior:**

- `deny` windows **block auto-sync only**. If `manualSync: true`,
  humans can still click "Sync" in the UI. If `manualSync: false`,
  nobody can sync during the window.
- `allow` windows **override** `deny` windows. So the above creates
  a 9-5 weekday window for prod auto-sync, with all other times denied.
- Sync windows are per-Application (the `applications:` field), not
  global.
- The controller pre-computes "is this window active right now?" on
  every reconcile, so window changes take effect within 3 minutes.

### The "deny everything by default" anti-pattern

Some teams try to do:

```yaml
syncWindows:
  - kind: deny
    schedule: '* * * * *'   # always deny
    applications: ['*']
```

This breaks ArgoCD — the auto-sync policy can't fire. Use `allow`
windows as the *enabling* rule:

```yaml
syncWindows:
  - kind: allow
    schedule: '0 9 * * 1-5'
    duration: 8h
```

This is the inverse and is the correct pattern.

---

## 10. Multi-tenancy and security boundaries

### AppProject is the primary boundary

The Apollo11 setup has one project, `apollo-airlines`, with 3
Applications in it. A larger org might have:

```
AppProject: data-platform    → 10 Applications, 1 namespace
AppProject: monitoring       → 5 Applications, 1 namespace
AppProject: apollo-airlines  → 3 Applications, 2 namespaces
```

Each project is a tenant. Cross-project Application references are
rejected by the controller. This is enforced server-side; no
`kubectl` workaround exists.

### AppProject roles (RBAC)

```yaml
spec:
  roles:
    - name: developer
      policies:
        - p, proj:apollo-airlines:developer, applications, get, apollo-airlines/*, allow
        - p, proj:apollo-airlines:developer, applications, sync, apollo-airlines/dev, allow
      groups:
        - dev-team
    - name: sre
      policies:
        - p, proj:apollo-airlines:sre, applications, *, apollo-airlines/*, allow
      groups:
        - sre-team
```

Then users get a JWT in `argocd-rbac-cm` (mapped from SSO) and
policies enforce what they can do. This is the **only** place to do
fine-grained RBAC in ArgoCD. The default `argocd-rbac-cm` denies
everything not explicitly allowed.

### Project-scoped clusters

For multi-cluster, register each remote cluster with a name in
`argocd-cm`:

```yaml
data:
  clusters: |
    - name: prod-east
      server: https://prod-east.eks.amazonaws.com
      config:
        bearerToken: <token>
        tlsClientConfig:
          insecure: false
          caData: <ca-bundle>
```

Then Applications reference it by name:

```yaml
spec:
  destination:
    name: prod-east    # references the cluster registration
    namespace: apollo-airlines-apps
```

The AppProject's `destinations` field enforces that the project can
only deploy to a specific subset of registered clusters. So a
`dev-team` project can have `destinations: [name: dev-cluster]`
and never accidentally deploy to prod.

### Cluster secret format

The `argocd clusters add` command writes a `Secret` of type
`argocd.argoproj.io/secret-type: cluster` in the `argocd` namespace.
The Secret has a `name`, `server`, `config` fields. To restrict
*which* team can use *which* cluster, the secret's `name` is the
key — the AppProject's `destinations[].server` or `[].name` must
match.

### Secrets in the repo

The repo has only `secrets:` references; the actual Secret data
should be in:

- A sealed-secrets / external-secrets operator
- Helm `--values-file` from a secret store (Vault, AWS Secrets Manager)
- A SOPS-encrypted file in the repo, decrypted by a `plugin` source

**Never** put raw `data:` in a public repo. ArgoCD will happily apply
it.

---

## 11. The CLI: the API the UI is built on

The `argocd` CLI is the most efficient way to operate ArgoCD. The UI
is a thin layer over the same gRPC API.

### Login

```bash
argocd login <server> --grpc-web
# Or with username/password (local users)
argocd login <server> --username admin --password "$PW" --insecure
# Or with SSO
argocd login <server> --sso
```

`--grpc-web` is required when you port-forward with
`kubectl port-forward` (the gRPC port 443 is blocked by most
browsers, so ArgoCD uses WebSocket in the port-forward case; the
CLI uses the WebSocket variant too).

### App lifecycle

```bash
# List
argocd app list -n apollo-airlines

# Get details (status, source, sync status)
argocd app get apollo11-dev -n apollo-airlines

# Sync
argocd app sync apollo11-dev --grpc-web
argocd app sync apollo11-dev --grpc-web --prune           # also prune
argocd app sync apollo11-dev --grpc-web --force           # bypass confirmations
argocd app sync apollo11-dev --grpc-web --async           # don't wait

# Diff (what would change)
argocd app diff apollo11-dev --grpc-web
argocd app diff apollo11-dev --grpc-web --revision HEAD   # diff against HEAD

# History (every sync)
argocd app history apollo11-dev --grpc-web

# Rollback
argocd app rollback apollo11-dev --grpc-web               # to previous
argocd app rollback apollo11-dev --grpc-web --id 3        # to specific revision

# Terminate a running operation
argocd app terminate-op apollo11-dev --grpc-web

# Delete
argocd app delete apollo11-dev --grpc-web                 # with cascade (prune)
argocd app delete apollo11-dev --grpc-web --cascade=false # orphan resources
```

### Refreshing vs syncing

These are different:

- **Refresh** (`argocd app get --refresh`) — re-check the source
  repo for new revisions. Updates the diff. No apply.
- **Sync** — apply the diff to the cluster.

You refresh first (to see the new state), then sync (to apply it).
With `automated: true`, the controller does both on a schedule.

### Manifest inspection

```bash
# Get the raw rendered manifests
argocd app manifests apollo11-dev --grpc-web

# Get the manifests as JSON (for jq)
argocd app manifests apollo11-dev --grpc-web -o json | jq '.[] | select(.kind=="Deployment")'

# Get a single resource from the live cluster
argocd app resources apollo11-dev --grpc-web
```

### Cluster and project management

```bash
# List registered clusters
argocd cluster list

# Add a remote cluster
argocd cluster add prod-east-context

# List projects
argocd proj list

# Show project details
argocd proj get apollo-airlines
```

### Useful flags

| Flag | What it does | When to use |
|---|---|---|
| `--grpc-web` | Use WebSocket transport | Always, with port-forward |
| `--server` | Override server URL | Scripts with multiple clusters |
| `--auth-token` | Use a JWT instead of login | CI/CD |
| `--header` | Add custom header | Corporate proxies |
| `--plainttext` | No TLS | DEV ONLY |
| `--insecure` | Skip cert verify | Self-signed certs |
| `--loglevel debug` | Verbose logging | Debugging sync issues |

### Scripting patterns

```bash
# Wait for all apps to be healthy (CI gate)
argocd app wait apollo11-dev apollo11-staging apollo11-prod \
    --health --timeout 300

# Wait for a specific sync to complete
argocd app sync apollo11-prod --async
argocd app wait apollo11-prod --operation --timeout 300

# List apps that are out of sync (alerting hook)
argocd app list -o name | xargs -I{} sh -c \
    'argocd app get {} -o json | jq -e ".status.syncStatus == \"OutOfSync\""'

# Roll back to a specific revision
argocd app history apollo11-prod -o json | \
    jq -r '.[1].id' | \
    xargs -I{} argocd app rollback apollo11-prod --id {}
```

### Contexts

`argocd context` lets you switch between multiple ArgoCD instances:

```bash
argocd context prod-argocd.example.com
argocd context dev-argocd.example.com

# All subsequent commands use the chosen context
argocd app list
```

Contexts are stored in `~/.config/argocd/config` and are per-user.

---

## 12. The UI: navigating efficiently

The UI is at `https://<argocd-server>/applications`. The default view
shows all Applications across all projects.

### The application detail page

For an Application, the key sections are:

| Section | What to look at |
|---|---|
| **Summary** | Sync status, health, source revision, last sync time |
| **Details** | repoURL, path, valueFiles, parameters — the full spec |
| **Sync Status** | `Synced` or `OutOfSync`, with a "Sync" button |
| **History** | Every sync, with revision, time, who, and a "Rollback" button |
| **Tree** | The full resource tree — Pods → Deployments → Services |
| **Network** | Visual graph of services + ingresses |
| **Logs** | The live tail of `kubectl logs` for any resource |
| **Events** | k8s events for any resource |
| **Diff** | Side-by-side comparison of live vs. desired |
| **Parameters** | Helm values, overridden by the App CR |
| **Manifest** | The raw rendered YAML |

### Keyboard shortcuts

- `g` then `a` — go to Applications
- `g` then `s` — go to Settings
- `/` — focus the search box
- `Esc` — close modals
- `?` — show all shortcuts

### The "live tail" feature

In the resource view, click on a Pod → "Logs" → enable "Follow". This
streams the pod's logs in real time. Equivalent to `kubectl logs -f`.

### App-of-apps

The UI has a concept of "App of Apps" — an Application whose source
manifest is a directory of more Application manifests. The UI shows
this as a nested tree. This is how you deploy "all of Apollo11" from
a single repo path.

The Apollo11 `applications/{dev,staging,prod}.yaml` files are
explicitly registered individually. To convert to App-of-Apps:

```
applications/
├── kustomization.yaml          # Lists all 3 files
├── dev.yaml
├── staging.yaml
└── prod.yaml
```

Then register one Application pointing at `applications/` with
`kustomize` rendering.

---

## 13. Notifications: alerting on sync events

The `argocd-notifications-controller` is a separate Helm chart that
ships alerts on ArgoCD events. Common triggers:

- `on-deployed` — fires after a successful sync
- `on-health-degraded` — fires when health.status flips to Degraded
- `on-sync-failed` — fires when a sync errors out
- `on-sync-status-unknown` — fires when ArgoCD can't determine status

### Subscriptions

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apollo11-prod
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: prod-deploys
    notifications.argoproj.io/subscribe.on-sync-failed.pagerduty: prod-pager
```

### Templates

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} synced successfully.
      Revision: {{.app.status.operationState.syncResult.revision}}
    slack:
      attachments: |
        [{
          "title": "{{.app.metadata.name}}",
          "color": "good",
          "fields": [
            {"title": "Revision", "value": "{{.app.status.operationState.syncResult.revision}}"}
          ]
        }]
  template.sync-failed: |
    message: |
      Sync of {{.app.metadata.name}} FAILED.
      Error: {{.app.status.operationState.message}}
    pagerduty:
      severity: error
```

### Services (the actual destinations)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: "<bot-token>"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  service.pagerduty: |
    serviceKey: $pagerduty-key
```

### Triggers on ApplicationSet

`ApplicationSet` has its own notification triggers for when
Applications are added/removed. Useful for "we just provisioned
cluster X, here's the resulting Applications."

---

## 14. Single Sign-On (SSO)

### The local users option (dev only)

```yaml
# argocd-cm
data:
  accounts.alice: apiKey
  accounts.bob: login
  accounts.admin: "*"  # superuser
```

```bash
# Set a password
argocd account update-password --account alice
# Or an API key
argocd account generate-token --account alice
```

Local users can't scale beyond a handful. For real orgs, use SSO.

### Dex + GitHub OAuth

```yaml
# argocd-cm
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $github-client-id
          clientSecret: $github-client-secret
          orgs:
            - name: apollo-org
              teams:
                - developers
                - sres
```

Then in `argocd-rbac-cm`:

```yaml
data:
  policy.csv: |
    p, role:developer, applications, get, apollo-airlines/dev, allow
    p, role:developer, applications, sync, apollo-airlines/dev, allow
    g, apollo-org:developers, role:developer
```

### OIDC direct (bypass Dex)

For Okta / Google Workspace / Auth0:

```yaml
data:
  oidc.config: |
    name: Okta
    issuer: https://apollo.okta.com
    clientID: $okta-client-id
    clientSecret: $okta-client-secret
    requestedScopes: ["openid", "profile", "email", "groups"]
    requestedIDTokenClaims: { "groups": { "essential": true } }
```

### SCIM provisioning

For auto-provisioning users from Okta/Google, enable SCIM in the
argocd server config:

```yaml
data:
  scmConfig: |
    github:
      - url: https://github.com/argoproj
        type: github
        branch: master
```

ArgoCD can also auto-sync from PRs (you have to enable the
`enableSCM` flag).

---

## 15. High availability and scaling

### The default (single-replica) is fine for a kind cluster

For a dev cluster with 3-5 Applications, the default install is
sufficient. The HA story is for production with hundreds of
Applications.

### Production HA topology

```
┌─────────────────────────────────────────────────────┐
│                    3x argocd-server (Deployment)    │
│                    behind an Ingress / Service LB   │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────┐
│           3x argocd-application-controller         │
│           (StatefulSet, leader election)           │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────┐
│           Nx argocd-repo-server (Deployment)       │
│           (HPA-driven by CPU)                      │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────┐
│           Redis Sentinel (3x)                      │
│           OR external managed Redis (ElastiCache)   │
└─────────────────────────────────────────────────────┘
```

### Tuning the application-controller

The application-controller is the bottleneck. For a cluster with
1,000 Applications, the defaults (20 status-processors, 10
operation-processors) are too low.

```yaml
# argocd-application-controller Deployment args
- --status-processors=50
- --operation-processors=20
- --self-heal-timeout=10
- --repo-server-timeout=120
```

Resource requests for the controller (per replica):

```yaml
resources:
  requests:
    cpu: "1"
    memory: 2Gi
  limits:
    cpu: "4"
    memory: 4Gi
```

### Tuning repoServer

repoServer is CPU- and memory-heavy during render. Use a HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  scaleTargetRef:
    name: argocd-repo-server
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### Sharding (multi-cluster control planes)

For very large installations, run multiple ArgoCDs, each managing a
subset of Applications. Use the `--shard` flag on the
application-controller:

```yaml
- --shard=0   # this controller handles apps with shard=0
```

```yaml
# Application
metadata:
  labels:
    argocd.argoproj.io/shard: "0"
```

The Application's shard label determines which controller
reconciles it. Useful for:
- Multi-tenant ArgoCDs (one per team)
- Multi-cluster (one ArgoCD per cluster region)
- Blast-radius reduction (one controller crash doesn't kill all apps)

### Resource requests matrix

| Component | CPU req | Mem req | CPU lim | Mem lim | Notes |
|---|---|---|---|---|---|
| argocd-server | 100m | 128Mi | 500m | 512Mi | Stateless, scale on count |
| argocd-application-controller | 1 | 2Gi | 4 | 4Gi | CPU spikes during sync |
| argocd-repo-server | 500m | 512Mi | 2 | 2Gi | CPU spikes during render |
| argocd-redis | 100m | 128Mi | 500m | 512Mi | Single replica is fine for dev |

---

## 16. Backup and disaster recovery

### What to back up

ArgoCD has 3 categories of state:

1. **Cluster state** (in etcd of the target cluster) — your workloads,
   their status, etc. ArgoCD can rebuild this from Git. **Not
   ArgoCD's problem.**
2. **ArgoCD system state** (CRDs, ConfigMaps, Secrets) — the
   AppProject, Application, cluster registrations, RBAC policies.
   This is in the `argocd` namespace.
3. **ArgoCD application state** (the Application CR's
   `status.history`, `status.operationState`) — historical sync
   records. This is also in etcd, in the same CRs as #2.

Categories 2 and 3 are what you back up.

### Back up the `argocd` namespace

```bash
kubectl get all,cm,secret,appproject,application -n argocd -o yaml \
  > argocd-backup-$(date +%Y%m%d).yaml
```

Or use Velero to back up the namespace with a schedule:

```bash
velero schedule create argocd-backup \
  --include-namespaces argocd \
  --schedule="@daily" \
  --ttl 720h
```

### What NOT to back up

- `argocd-redis` data — it's a cache, regenerable.
- The Application's *runtime* state (the `status.conditions` that
  are still updating) — back up the CR definitions, not the live
  status. The controller will re-derive status on first reconcile.

### Disaster recovery procedure

1. **Cluster total loss** — ArgoCD in `argocd` namespace is gone.
   - `kubectl apply -f argocd-backup.yaml` (the install.yaml + your
     customizations)
   - Re-register remote clusters (`argocd cluster add ...`)
   - Applications will reconcile against Git and rebuild the cluster
     state.

2. **Single Application deletion** — App CR is gone, but the
   workloads it created are still running (no finalizer).
   - `kubectl apply -f application.yaml` — controller sees the live
     resources match the desired, marks Synced, no action needed.
   - If `resources-finalizer` was set, the resources were already
     deleted.

3. **Repo loss** — GitHub is down / repo deleted.
   - This is a real outage. ArgoCD will mark Applications as
     `Unknown` (can't reach source).
   - Mitigation: mirror the repo to GitLab/Gitea. ArgoCD supports
     multiple sources on a single Application.
   - The cluster keeps running (it converged on the last good
     revision).

4. **Helm chart loss** — chart is hosted at a URL that's down.
   - Helm repos are different from Git repos. ArgoCD fetches the
     chart with `helm pull` (or `helm template` for a path-based
     source).
   - For a path-based source (which Apollo11 uses), the chart is
     in the same Git repo as the manifests. If the repo is gone,
     see #3.

### Restoring across clusters

The Apollo11 `argocd/scripts/bootstrap.sh` is itself a backup-and-
restore mechanism: it knows how to install ArgoCD and register all 3
Applications from scratch. Run it on a new cluster and you have
Apollo11 in 5 minutes.

---

## 17. ApplicationSets: templated fan-out

The `ApplicationSet` CR generates multiple Application CRs from a
template + a list of inputs. Inputs come from "generators" — a
plugin-style hook.

### Generator types

| Generator | Input | Use case |
|---|---|---|
| `list` | Hardcoded YAML list | Few envs, known at config time |
| `git` | A directory tree in a Git repo | Multi-tenant deployments, "deploy all of /clusters/*" |
| `cluster` | All registered clusters | Hub-and-spoke to every cluster |
| `matrix` | Cartesian product of two lists | "3 clusters × 3 envs" = 9 apps |
| `merge` | Combine two generators | "For each cluster, deploy from each of these 2 repos" |
| `plugin` | Custom external tool | "Pull from our CMDB" |

### `list` generator (the simplest)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apollo11
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: in-cluster
            env: dev
            tag: dev
            pdb: "false"
          - cluster: in-cluster
            env: staging
            tag: latest
            pdb: "false"
          - cluster: prod-east
            env: prod
            tag: v1.0.0
            pdb: "true"
  template:
    metadata:
      name: 'apollo11-{{env}}'
    spec:
      project: apollo-airlines
      source:
        repoURL: https://github.com/darshan/Apollo11
        targetRevision: HEAD
        path: stages/stage5/helm/apollo11
        helm:
          valueFiles: ['values-{{env}}.yaml']
          parameters:
            - { name: image.tag, value: '{{tag}}' }
            - { name: pdb.enabled, value: '{{pdb}}' }
      destination:
        server: '{{cluster}}'
        namespace: apollo-airlines-apps
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

This is a strict superset of the three explicit Application CRs in
`applications/`. The trade-off: explicit CRs are easier to read for
learning, but an ApplicationSet is easier to extend for "add a new
env" (one list entry, no new file).

### `git` generator (multi-tenant by directory)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/darshan/cluster-config
        revision: HEAD
        directories:
          - path: clusters/*
      template:
        metadata:
          name: 'addon-{{path.basename}}'
        spec:
          project: platform
          source:
            repoURL: https://github.com/darshan/cluster-config
            revision: HEAD
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc
            namespace: '{{path.basename}}'
```

This deploys every directory under `clusters/*` as its own
Application in its own namespace. Common pattern for "we have N
clusters and N addons, render the matrix."

### `cluster` generator (hub-and-spoke)

```yaml
generators:
  - clusters: {}
template:
  metadata:
    name: 'apollo11-{{nameNormalized}}'
  spec:
    source: { ... }
    destination:
      name: '{{name}}'
      namespace: apollo-airlines-apps
```

Empty `clusters: {}` means "use all registered clusters." Add
`selector.matchLabels.env=prod` to filter.

### Sync policy at the ApplicationSet level

```yaml
spec:
  syncPolicy:
    preserveResourcesOnDeletion: false  # default
  template:
    spec:
      syncPolicy:
        automated: { ... }   # per-Application
```

`preserveResourcesOnDeletion: true` keeps the cluster resources
when the ApplicationSet (or a generated Application) is deleted. The
default is to prune.

### ApplicationSet controller

`argocd-applicationset-controller` is a separate Helm chart. The
default `install.yaml` does NOT include it. Install it explicitly:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/appset-install.yaml
```

---

## 18. Multi-cluster GitOps

Three patterns:

### Pattern 1: Hub-and-spoke (most common)

One ArgoCD in a "control plane" cluster, manages all other clusters.

```
  ┌────────────────────────────────────┐
  │  mgmt-cluster                       │
  │  ┌──────────────────────────────┐   │
  │  │  ArgoCD                     │   │
  │  │  - ApplicationSet with      │   │
  │  │    cluster generator        │   │
  │  │  - Each Application deploys │   │
  │  │    to a remote cluster      │   │
  │  └──────────────────────────────┘   │
  └────────────────────────────────────┘
       │           │           │
       ▼           ▼           ▼
  ┌────────┐  ┌────────┐  ┌────────┐
  │  dev   │  │ staging│  │  prod  │
  └────────┘  └────────┘  └────────┘
```

The remote clusters only need:
- A `Secret` of type `argocd.argoproj.io/secret-type: cluster` in
  the *hub*'s `argocd` namespace, pointing at the spoke's API server
- Network reachability from the hub to the spoke's API server
  (cluster-to-cluster)

### Pattern 2: One ArgoCD per cluster

Each cluster has its own ArgoCD, each manages its own Applications.

```
  ┌────────┐  ┌────────┐  ┌────────┐
  │  dev   │  │ staging│  │  prod  │
  │ ┌────┐ │  │ ┌────┐ │  │ ┌────┐ │
  │ │argocd││  │ │argocd││ │ │argocd││
  │ │────│ │  │ │────│ │  │ │────│ │
  │ │app │ │  │ │app │ │  │ │app │ │
  │ └────┘ │  │ └────┘ │  │ └────┘ │
  └────────┘  └────────┘  └────────┘
```

Pros: cluster isolation, no cross-cluster trust.
Cons: N copies of the ApplicationSet config, no centralized audit.

### Pattern 3: Hybrid (control plane + spoke)

The hub manages *infrastructure* (operators, cert-manager, ingress,
Argo Rollouts) and *bootstrap* the ArgoCD in each spoke. The spoke
ArgoCD manages *workloads*.

This is the most complex but the most common in mature orgs. It's
beyond the scope of Apollo11 but worth knowing exists.

### Cluster registration in detail

```bash
# Add a cluster (creates a Secret in argocd namespace)
argocd cluster add spoke-context \
  --name spoke-1 \
  --cluster-endpoint https://spoke-1.example.com:6443 \
  --cluster-ca-file /path/to/ca.crt
```

Or by hand (for CI/CD):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-spoke-1
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: spoke-1
  server: https://spoke-1.example.com:6443
  config: |
    {
      "bearerToken": "<service-account-token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-encoded-ca>"
      }
    }
```

The Secret's `name` is referenced by Application/ApplicationSet
`destination.name`. The Secret's `server` must match exactly
(including port and trailing slash) what the Application declares.

### Project + cluster combination

```yaml
# AppProject
spec:
  destinations:
    - name: spoke-1
      namespace: apollo-airlines-apps
    - name: spoke-2
      namespace: apollo-airlines-apps
    - server: https://kubernetes.default.svc
      namespace: apollo-airlines-apps
```

The `name:` form is preferred — it's stable across cluster
re-registrations (the secret's `name` doesn't change even if the
`server` URL changes).

---

## 19. Progressive delivery with Argo Rollouts

Argo Rollouts is a separate project. It extends the Deployment CRD
to support canary, blue/green, A/B testing, and traffic shaping.
The full Rollouts story is Stage 10 of Apollo11; this section is
the integration with ArgoCD.

### The CRD change

```yaml
# Was
kind: Deployment
# Is
kind: Rollout
```

ArgoCD will happily render and apply Rollouts instead of
Deployments. The Application's diff will show the change; with
`automated: true` it'll sync.

### Traffic shaping

Rollouts work with ingress controllers to shift traffic:

- **ALB / Nginx** — annotation-based traffic split
- **Istio / Linkerd** — VirtualService-based split
- **Traefik / Envoy** — header-based routing

The Apollo11 access stack (Envoy Gateway) is compatible. The
Rollout would declare an `EnvoyTrafficRouting` plugin (provided by
Argo Rollouts).

### Rollback via ArgoCD

Because Rollouts extend the `apps/v1` Deployment API contract, an
ArgoCD `argocd app rollback` reverts the Rollout manifest, and the
Rollout controller converges the live state. The two systems
cooperate: ArgoCD manages the *spec*, the Rollout controller
manages the *traffic* and the *phased rollout*.

### Stage 10 details

Apollo11's Stage 10 adds Linkerd (service mesh), Argo Rollouts
(canary for booking + search), and Chaos Mesh. The GitOps layer
(ArgoCD) stays unchanged — same Application pointing at the same
chart, but the chart's Deployments are now Rollouts.

---

## 20. Performance tuning and resource limits

### The 1000-Application benchmark

A well-tuned ArgoCD on a single node can handle ~1,000
Applications. The bottlenecks are:

1. **application-controller** — reconciliation is single-threaded
   per Application. The controller has goroutine pools (status
   and operation processors).
2. **repoServer** — render time per Application. Helm-heavy
   charts with `lookup` calls can take 5+ seconds.
3. **Redis** — caches the rendered manifests, not the diff
   computation. Cache hit rate matters.
4. **API server** — each diff is a List call. For 1,000 apps
   with 50 resources each, that's 50,000 List calls per
   reconcile. The default 3-minute window creates a thundering
   herd.

### The tuneables

```yaml
# application-controller
--status-processors=50     # default 20
--operation-processors=20  # default 10
--self-heal-timeout=10     # default 5s
--repo-server-timeout=120  # default 60s
--cache-expiration=24h     # how long to cache Application status
```

```yaml
# repoServer
--repo-cache-expiration=24h
--max-connections=100
--disable-helm=false
```

```yaml
# Application override
spec:
  ignoreDifferences: [...]
  syncPolicy.retry.backoff.maxDuration: 5m
```

### The hard limits

| Limit | Default | Where to set |
|---|---|---|
| Max Applications per controller | ~1000 (tuning-bound) | --status-processors |
| Max resources per Application | ~5000 (API bound) | none — split into multiple apps |
| Max CRD resource size | 256KB (apply) / no limit (SSA) | use ServerSideApply=true |
| Render time per Application | 5s typical, 30s worst | chart simplicity |

### When to shard

If you have >1,000 Applications, *shard* the controller:

```yaml
# Controller for shard 0
- --shard=0
# Controller for shard 1
- --shard=1
```

```yaml
# Application
metadata:
  labels:
    argocd.argoproj.io/shard: "0"  # or "1"
```

Sharding is also useful for *tenant isolation* — one shard for
"data" apps, one for "user-facing" apps. A bug in one shard
doesn't affect the other.

---

## 21. Common failure modes and debugging

### Application won't sync

```
1. Check sync status
   argocd app get <name> -o yaml | yq '.status.conditions'

2. Common conditions:
   - "ComparisonError"   → the diff failed. Usually a render error in the chart.
   - "SyncError"         → the apply failed. Look at the message.
   - "InvalidSpecError"  → the source couldn't be parsed.

3. Re-render the chart by hand
   helm template <chart> -f <values>  # to see what ArgoCD saw

4. Check the application-controller logs
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

### Application is OutOfSync but you didn't change anything

```
1. Check `ignoreDifferences` — is the field ignored?
2. Check the controller for "drift detected" events
3. Run `argocd app diff <name>` to see the actual diff
4. If it's a SSA-managed field, check `managedFieldsManagers`
5. If it's status-only, it's not actually drift (ArgoCD sometimes
   shows it that way; the actual sync is still correct)
```

### Application is Healthy but not actually running

ArgoCD's "Healthy" check is shallow for custom resources. For
Deployments, it checks `status.readyReplicas == spec.replicas`. For
a CRD without a known health check, it returns "Healthy" if the
resource exists.

Fix: write a `lua` health check in `argocd-cm`:

```yaml
data:
  resource.customizations.health.<group>_<kind>: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Running" then
        hs.status = "Healthy"
      elseif obj.status.phase == "Failed" then
        hs.status = "Degraded"
        hs.message = obj.status.message
      end
    end
    return hs
```

### Application is Healthy but pods are CrashLoopBackOff

ArgoCD checks Deployment-level readiness, not pod-level. A
Deployment with 0 readyReplicas (because all pods are crashing)
would show `Healthy` if the chart's `replicas` is 0, or
`Progressing` if replicas > 0.

Always cross-reference with `kubectl get pods`.

### Self-heal not working

```
1. Confirm `syncPolicy.automated.selfHeal: true` on the Application
2. Confirm the controller is running
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
3. Check for ignored fields
   argocd app diff <name>  # if the drift is ignored, selfHeal won't fire
4. Check for SSA conflicts
   kubectl get deploy <name> -o yaml | yq '.metadata.managedFields'
   # If another manager owns the field, ArgoCD can't revert it
```

### RepoServer OOM

The symptom: repoServer pods restart with OOMKilled. The cause:
a chart with a Helm `lookup` call that returns the entire k8s API
state, or a Kustomize with a remote build that pulls MBs of data.

Mitigation:

```yaml
# repoServer resources
resources:
  requests: { cpu: 1, memory: 1Gi }
  limits:   { cpu: 4, memory: 4Gi }
```

Or fix the chart — `lookup` calls in Helm should target small
subtrees (`lookup "v1" "ConfigMap" "" ""` returns everything,
which is OOM-bait).

### Cert errors on first install

The argocd-server cert is generated by an init container that
talks to the k8s API. If the API server is slow, the init
container times out. Fix:

```bash
kubectl logs -n argocd argocd-server-<pod> -c argocd-server
# Look for "x509: certificate signed by unknown authority"
```

Workaround: use the `--insecure` flag (dev only) or pre-provision
a cert with cert-manager (prod).

### ArgoCD and the cluster's clock

ArgoCD uses HMAC tokens for session auth. If the cluster's clock
is off by more than 5 minutes, all logins fail. Fix: run
`chrony` or `ntpdate` on every node.

### Webhook signature failures

If you have GitHub webhooks configured (push notifications instead
of polling), the HMAC secret must match what's in `argocd-secret`.
A regen of the secret without updating the webhook URL causes
silent sync delays (ArgoCD falls back to polling).

---

## 22. Anti-patterns to avoid

### Anti-pattern 1: Imperative sync from CI

```bash
# ❌ DON'T do this in CI
argocd app sync apollo11-prod
```

This bypasses the GitOps contract. The cluster state is now a
function of (CI run, Git), not just Git. If CI runs twice with
different code, the second run wins — even if it didn't go
through a PR review.

**The correct pattern:** CI builds and pushes the image. ArgoCD
detects the new image (via Helm `image.tag` in the chart values
or Kustomize `images:` override) and syncs.

### Anti-pattern 2: ArgoCD managing ArgoCD

Don't put the ArgoCD install under ArgoCD management. It
works (ArgoCD can manage itself), but the failure mode is brutal:
if ArgoCD can't render its own manifests, you can't fix it
through ArgoCD.

Mitigation: keep ArgoCD install outside any Application, and
use the `--self-managed` flag to disable self-bootstrap.

### Anti-pattern 3: One big Application for everything

```yaml
# ❌ 50 Deployments in one Application
spec:
  source:
    path: deploy
```

The diff is huge, the sync is slow, one bad resource blocks the
rest, and you can't sync half of them.

**The correct pattern:** one Application per deployable unit. A
Helm chart is usually one Application. A set of related
microservices with their own lifecycle is 5-10 Applications.

### Anti-pattern 4: Setting `selfHeal: true` in prod

```yaml
# ❌
syncPolicy:
  automated:
    selfHeal: true   # ← don't do this in prod
```

In a real prod incident, SREs need to `kubectl scale` or `kubectl
edit` a Deployment to recover. selfHeal reverts the change and
you've now fought the controller and the incident.

Use `selfHeal: false` in prod; rely on `argocd app sync` for
rollbacks.

### Anti-pattern 5: Secrets in plaintext in Git

```yaml
# ❌ NEVER
data:
  POSTGRES_PASSWORD: cGFzc3dvcmQ=
```

Use one of:
- External Secrets Operator (pulls from AWS Secrets Manager / Vault)
- Sealed Secrets (controller decrypts with a cluster key)
- SOPS (Mozilla's `sops` tool, encrypted in Git, decrypted at render time)
- Helm `--values` from a secret store

### Anti-pattern 6: Sync waves as a substitute for proper dependencies

If Application A needs Application B to be ready, you have two
choices:
1. **Sync waves** (ArgoCD-native, ties deploys together)
2. **Readiness probes + retries** (the app waits for its dependency)

Sync waves work for the initial deploy. They DON'T work for the
steady state — Application A's reconciler doesn't re-trigger when
Application B comes back after a crash. Use probes for steady-
state, waves for bootstrap.

### Anti-pattern 7: Hardcoding image tags in Application CRs

```yaml
# ❌
source:
  helm:
    parameters:
      - name: image.tag
        value: 1.2.3-abc123    # ← this lives in the Application CR
```

The image tag is build-time metadata. It should live in the values
file, the chart's `Chart.yaml`, or a CI-generated values override.
Putting it in the Application CR means you have 2 places to update
for a release.

Apollo11's `applications/*.yaml` does have `image.tag` as a
parameter — this is intentional for the teaching demo (so a
student can see "this is the tag we'd ship"). In a real prod
setup, the tag would be in a per-env values file and the
Application CR would have no `image.tag` parameter at all.

### Anti-pattern 8: Polling instead of webhooks

Default ArgoCD polls the Git repo every 3 minutes. This is fine
for low-frequency deploys but causes a 3-minute lag for "I just
merged, why isn't it deployed?"

Webhooks eliminate the lag. Configure your Git host:

```yaml
# argocd-cm
data:
  webhook.github: "github-webhook-secret"
```

Then in GitHub: Settings → Webhooks → Add
`https://argocd.example.com/api/webhook` with the secret. ArgoCD
reconciles within 1 second of the push.

### Anti-pattern 9: AppProject scope too narrow

```yaml
# ❌ One AppProject per Application
- apollo-airlines-dev
- apollo-airlines-staging
- apollo-airlines-prod
```

Three projects with three Applications each. This is project
proliferation — it makes RBAC and audit harder. Use **one project
per team/tenant**, with N Applications inside it. Apollo11's
`apollo-airlines` project with 3 Applications is the right
granularity.

### Anti-pattern 10: Ignoring `orphanedResources`

```yaml
spec:
  orphanedResources:
    warn: false    # ❌
```

This is your safety net. With `warn: true`, ArgoCD tells you when
a resource exists in the cluster that no Application claims. This
catches:
- `kubectl apply` side-effects
- Old helm releases
- Manually-created ConfigMaps

Always leave `warn: true` (or escalate to `ignore: []` with
explicit allowlist).

---

## 23. Glossary

| Term | Definition |
|---|---|
| **Application** | A CR that defines a single source → destination → sync policy binding. |
| **AppProject** | A CR that groups Applications and enforces scope (source repos, destination clusters/namespaces, RBAC). |
| **ApplicationSet** | A CR that generates N Applications from a template + a generator. |
| **Sync** | The act of making the live cluster state match the desired state from Git. |
| **Self-heal** | Continuous sync that reverts out-of-band `kubectl edit` changes. |
| **Prune** | Deleting cluster resources that disappeared from the source manifest. |
| **Drift** | The difference between desired and live state. |
| **Reconciliation loop** | The controller's continuous check-and-apply cycle (default 3 minutes). |
| **Desired state** | The set of resources the chart/manifests produce when rendered. |
| **Live state** | The set of resources currently in the cluster's API server. |
| **RepoServer** | The ArgoCD component that fetches + renders the source. |
| **Application Controller** | The ArgoCD component that computes diffs and applies them. |
| **App-of-Apps** | An Application whose source is a directory of more Application manifests. |
| **Hook** | A resource (usually a Job) that runs before/after the main sync, not part of the workload. |
| **Sync wave** | A numeric annotation that orders Application syncs within a multi-app deploy. |
| **Sync window** | A time-bounded rule that gates auto-sync (allow/deny). |
| **Source type** | How the source manifests are produced (Helm, Kustomize, directory, plugin). |
| **Hub-and-spoke** | Multi-cluster pattern: one ArgoCD in a hub cluster manages N spoke clusters. |
| **Sharding** | Splitting the Application controller's workload across N controllers by `shard` label. |
| **Refresh** | Re-check the source repo for new revisions (read-only). |
| **Operation** | A sync action in progress; tracked in `status.operation`. |
| **Finalizer** | A k8s metadata entry that delays resource deletion until cleanup runs. |
| **SSA** | Server-Side Apply (k8s 1.16+); the API server owns the resource, clients submit partials. |
| **CRD** | CustomResourceDefinition; how k8s extends its API. |
| **WebHook** | An HTTP endpoint that ArgoCD exposes for Git providers to call on push. |
| **Dex** | An OIDC bridge that ArgoCD uses for SSO. |

---

## Where to go from here

- **Apollo11 `argocd/DEMO.md`** — hands-on walkthrough of the
  Apollo11 GitOps setup.
- **ArgoCD docs** — https://argo-cd.readthedocs.io/en/stable/
- **Argo Rollouts** — Stage 10 of Apollo11, extends Deployments to
  canary/blue-green.
- **Argo Workflows** — separate project, for CI pipelines and
  batch jobs. Different problem space.
- **External Secrets Operator** — to manage secrets in ArgoCD
  without putting them in Git.
- **ApplicationSet docs** — https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/

---

*Last updated: 2025-06-11. ArgoCD v2.13.x. The Apollo11 setup uses
ArgoCD v2.13.2 specifically; some features (ApplicationSet
`matrix.merge` generators, post-delete hooks) are 2.12+.*
