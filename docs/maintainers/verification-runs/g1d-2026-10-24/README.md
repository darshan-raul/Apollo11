---
title: "G1d — Argo CD live lifecycles for Stages 5–7 (2026-10-24)"
description: "Argo CD reconciling GitHub main (90b5120) with the published GHCR images: Stage 5 passes; Stage 6/7 do not converge on a 6-core host; two script defects found."
---

# G1d — Argo CD live lifecycles, Stages 5–7 (2026-10-24)

Source: the real path a learner uses. The Applications track
`https://github.com/darshan-raul/Apollo11.git` at `HEAD` (`90b5120`), and the
images come from GHCR (`ghcr.io/darshan-raul/apollo11/stageN/*:latest`,
published by the 2026-10-24 CI run). No local Git fixture, no preloaded images.
Cluster: `kind-apollo11`, 3 nodes, 6 CPUs, 16 GB host.

| Stage | Verify | Result |
|---|---|---|
| 5 | **74/74** | Pass: three tenants, AppProject boundary, real replica-drift self-heal; purge clean |
| 6 | 84/88 | Not converged: after the 900 s wait, dev/staging `Synced/Degraded`, shared observability `OutOfSync/Progressing`. All workload-readiness checks passed. Host load average peaked at 10. |
| 7 | 83/88 | Not converged: dev/staging Degraded, observability `OutOfSync/Degraded`, Grafana not ready. Host load average peaked at **91** on 6 cores, with Pods stuck in `ContainerCreating` (`stage7-diagnostics.log`) |

`prod` is `OutOfSync/Missing` by design (manual sync) in every stage, and the
verifiers expect that.

## Defects found

1. **The Argo verifiers never waited for convergence (fixed).** `verify.sh` ran
   its readiness checks immediately after `bootstrap.sh --sync`, so it reported
   a cluster still pulling images. The first Stage 5 attempt scored 50/74 with
   every workload "not ready" (`attempt-no-convergence-wait/`). All three
   verifiers now wait up to `ARGO_CONVERGE_TIMEOUT` (default 900 s) for
   automated Applications to be `Synced/Healthy`, then check. Stage 5 went to
   74/74. This may also explain the 2026-10-19 Stage 6/7 results (79/88, 80/88).
2. **Argo teardown can strand the `argocd` namespace (open, tracker G36).**
   Stage 7 `teardown.sh --purge` force-deleted the Argo CD controller while two
   Applications still had `resources-finalizer` pending. Nothing could clear the
   finalizers, the namespace hung in Terminating, the script exited 1, and about
   40 CRDs plus the Argo/Envoy/MetalLB/Prometheus ClusterRoles were left
   behind (`stage7/residue.log`, `stage7/teardown.log`). Cleanup: the tenant
   namespaces were already gone, so the two finalizers were cleared by hand,
   then `teardown.sh --purge` reran cleanly (`stage7/manual-cleanup.log`). The
   cluster ended with zero residue.

## Capacity finding (tracker G37)

On this host the Stage 6/7 Argo layout (dev and staging tenants, each a full
10-workload stack, plus the shared observability stack, all images pulled from
registries) does not converge within 15 minutes. Stage 5, without
observability, does. This needs either a documented larger minimum (G13) or a
lighter default layout for local kind.
