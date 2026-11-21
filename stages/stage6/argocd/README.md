---
title: "Stage 6 — Argo CD GitOps Module"
description: "Three isolated Apollo Airlines environments plus one shared observability Application."
---

# Stage 6 — Argo CD GitOps Module

This optional module delivers Stage 6 declaratively. Argo CD reconciles three
isolated application environments while a fourth Application owns the shared
observability stack.

## Ownership model

| Application | Source | Destination | Sync policy |
|---|---|---|---|
| `apollo11-dev` | Stage 6 Helm chart + dev values | dev apps/UI namespaces | automated, prune, self-heal |
| `apollo11-staging` | Stage 6 Helm chart + staging values | staging apps/UI namespaces | automated, prune, self-heal |
| `apollo11-prod` | Stage 6 Helm chart + prod values | prod apps/UI namespaces | manual |
| `apollo11-observability` | generated plain manifests | `apollo-observability` | automated, prune, self-heal |

The tenant Applications set `observability.enabled=false`. This is important:
Prometheus, Grafana, Tempo, Loki, and the per-node collectors are cluster-wide
shared services, not three competing copies. The shared Application owns those
namespaced resources exactly once.

Cluster-scoped prerequisites remain platform-owned and are installed by
`scripts/bootstrap.sh`:

- Envoy Gateway and Gateway API CRDs;
- MetalLB and its CRDs;
- Prometheus Operator and monitoring CRDs;
- tenant and observability namespaces; and
- the shared GatewayClass, address pool, and discovery RBAC.

The AppProject denies Application-owned cluster-scoped resources and limits
destinations to the six tenant namespaces plus `apollo-observability`.

## Static validation

Run before touching a cluster:

```bash
bash scripts/validate.sh
```

It renders every source exactly as Argo CD will and asserts ownership and
resource boundaries. The verified counts are:

| Source | Resources |
|---|---:|
| dev tenant | 58 |
| staging tenant | 58 |
| prod tenant | 60 |
| shared observability | 44 |

## Live workflow

Argo CD can only reconcile content available at a Git revision. Push the Stage
6 work to the configured repository first, or point all Applications at an
authorized test repository containing the same tree.

```bash
bash install.sh --offline
bash scripts/bootstrap.sh
bash scripts/verify.sh
```

Use `--sync` with bootstrap to request immediate dev/staging reconciliation.
Production remains manual unless `--include-prod` is explicitly supplied.

To use preloaded kind images during a local demonstration:

```bash
bash scripts/bootstrap.sh \
  --image-repository apollo11 \
  --repo-url https://github.com/OWNER/Apollo11.git
```

## Cleanup

```bash
bash scripts/teardown.sh
bash uninstall.sh
```

The teardown removes Applications first so their foreground finalizers can
delete managed resources, then removes the shared platform in dependency order.
See `scripts/teardown.sh --help` for purge behavior.

## Files

```text
argocd/
├── applications/
│   ├── dev.yaml
│   ├── staging.yaml
│   ├── prod.yaml
│   └── observability.yaml
├── platform/
│   ├── platform.yaml
│   └── observability/{kustomization.yaml,generated.yaml}
├── projects/project.yaml
├── scripts/{bootstrap,validate,verify,teardown}.sh
├── bundles/argocd-install.yaml
├── install.sh
└── uninstall.sh
```

`generated.yaml` is derived from the Stage 6 chart and committed as a plain
manifest so the shared Application does not require a second chart ownership
mode. Regenerate it whenever an observability template changes, then rerun
`scripts/validate.sh`.
