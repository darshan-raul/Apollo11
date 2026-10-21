---
title: "Fix pass — 2026-10-22"
description: "Live evidence for the review fixes: image gate, Stage 5–7 lifecycles, capacity profile, and Stage 10 missions."
---

# Fix pass — 2026-10-22

Commit `1ac5c66` plus the uncommitted later-stage work and this pass's fixes.
Fresh `kind-apollo11` (3 nodes, Kubernetes v1.37.0, 6 cores, 16 GB). Images were
rebuilt by `apply.sh` on the first run of each stage. Each run directory holds
`apply`, `verify`, lab, `teardown` and `residue` logs plus a `summary.txt`.

## Image gate (`trivy/`)

All 18 Stage 5–7 images built from the upgraded Dockerfiles pass CI's gate
(`--ignore-unfixed --severity CRITICAL,HIGH`, Trivy 0.75.0): zero fixable HIGH or
CRITICAL findings. Before the upgrade, `apollo11/search` alone had 2 CRITICAL and
54 HIGH. `ci-local.log` is `test/ci.sh` passing after the dependency upgrade.

## Lifecycles

| Run | Verify | Labs | Residue after `--purge` |
|---|---|---|---|
| Stage 5 Helm/dev | 174/174 | – | none |
| Stage 5 Kustomize/dev | 163/163 | – | none |
| Stage 6 Helm/dev | 212/212 | trace-test FAILED (identity, see below); observability-lab pass | none |
| Stage 6 Kustomize/dev | 201/201 | – | none |
| Stage 6 Helm/dev `-identity-fix` | 212/212 | trace-test, observability-lab pass | none |
| Stage 6 Kustomize/dev `-identity-fix` | 201/201 | – | none |
| Stage 7 Helm/dev | 227/227 | trace-test, observability-lab pass; capacity: 3rd replica Pending | none |
| Stage 7 Kustomize/dev | 216/216 | – | none |
| Stage 7 Helm/dev `-spread-fix` | 227/227 | trace-test, observability-lab pass; capacity 1→2→3, no Pending | none |
| Stage 7 Kustomize/dev `-spread-fix` | 216/216 | – | none |

"None" means only the built-in `system:monitoring` ClusterRole and binding remain.
The `-spread-fix` and `-identity-fix` runs include both fixes below.

## Defects found and fixed in this pass

- **Search third replica stayed Pending under load.** The `DoNotSchedule`
  spread (G16) counted the tainted control-plane node as an empty domain, so a
  third replica on two workers broke `maxSkew: 1`. The capacity run shows the
  HPA at 3 desired with one Pod Pending for the rest of the run. Fix:
  `nodeTaintsPolicy: Honor`; `verify.sh` now checks it. The rerun placed 2 + 1
  across both workers with no Pending samples.
- **Identity stalled at its 128Mi limit (Stages 6–7).** In the first Stage 6
  run, identity's cgroup peak was 134,205,440 bytes against a 134,217,728 limit;
  probes and booking's user check timed out, so `trace-test.sh` got a 502. This
  predates the dependency upgrade: the old image imports in 91.9 MB, the new one
  in 84.8 MB. Fix: a `python` tier (200m / 256Mi, Guaranteed QoS) for identity.
  The rerun peaked at 148 MB with CPU throttling down from ~30 s to 5.5 s
  (`stage6-helm-dev-identity-fix/identity-cgroup.txt`).
- **Stage 6/7 `verify.sh` leaked port-forwards.** `kubectl` is a shell function,
  so `$!` was a subshell PID and `kill` missed the real process. Now runs
  `command kubectl` directly; the next verify left no port-forwards.

## Capacity profile (`stage7-helm-dev*/capacity-*`)

Normal CPU target (70%) and stabilization windows, 14-minute ramp 10→200 req/s
through the Envoy Gateway. Both runs: ~81,900 requests, 0 failed, p95 31 ms then
27 ms. k6 exits 99 only because 13 and 16 iterations were dropped while no VU was
free during short latency spikes (max 2.6 s); per `PERFORMANCE.md`, that marks
the tested boundary. The HPA scaled 1→2→3.

## Stage 10 missions

- **CloudNativePG:** `verify.sh` passed on the cluster the earlier session
  created: failover in 7 s, row survived, logical restore matched; teardown
  removed the cluster and private kubeconfig (`cnpg-*.log`).
- **Falco:** three `apply.sh` attempts failed downloading the chart from GitHub
  release assets (network timeouts, `falco-apply-attempt*`); the fourth passed.
  `verify.sh` passed; the matching event is in `falco-detection-events.log`;
  teardown removed the cluster.

## Not covered

Argo CD Stage 6/7 live reruns, Helm/staging, and the hosted GitHub Actions run
(G15) were not repeated in this pass.
