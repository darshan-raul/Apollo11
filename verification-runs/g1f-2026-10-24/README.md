---
title: "G1f — Stage 4–7 lifecycles on the non-root images (2026-10-24)"
description: "Fresh Helm and Kustomize dev lifecycles for Stages 5–7, plus Stage 4, after the G17 and G21 code changes."
---

# G1f — Stage 4–7 lifecycles on the non-root images (2026-10-24)

Code: Apollo11 `6bc371b` plus the uncommitted G21 identity shutdown fix and the
Stage 4 verifier fix below. Cluster: `kind-apollo11`, three nodes, Kubernetes
v1.37.0. Each run built its stage's images (Kustomize reused the Helm run's),
applied, verified, checked the runtime UID of every app Deployment
(`uids.txt`), ran the stage's labs, purged, and audited residue. Host load
average rose to 4–8 on 6 cores during Stage 7, above the S2 "quiet host"
guidance, and every run still passed.

| Run | Verify | Labs | Runtime UIDs | Residue after purge |
|---|---|---|---|---|
| Stage 4 | **149/149** | (built into verify: SIGTERM, PDB eviction, placement) | 100 (named `apollo` user), frontend 101 | none |
| Stage 5 Helm/dev | **174/174** | – | 10001, frontend 101 | built-in `system:monitoring` only |
| Stage 5 Kustomize/dev | **163/163** | – | 10001, frontend 101 | same |
| Stage 6 Helm/dev | **212/212** | `trace-test.sh` pass, `observability-lab.sh` pass | 10001, frontend 101 | same |
| Stage 6 Kustomize/dev | **201/201** | – | 10001, frontend 101 | same |
| Stage 7 Helm/dev | **227/227** | `trace-test.sh`, `observability-lab.sh`, `scaling-lab.sh run` pass | 10001, frontend 101 | same |
| Stage 7 Kustomize/dev | **216/216** | – | 10001, frontend 101 | same |

Every verifier includes passenger login, so identity's direct `bcrypt` (G17)
works against the seeded hashes in all three stages. The counts equal the
2026-10-22 counts, now on the shipped images.

## Defect found and fixed during this pass

**The Stage 4 verifier could abort silently.** In
`stages/stage4/scripts/verify.sh` (which runs `set -euo pipefail`), the
graceful-termination check waited with
`kubectl wait --for=condition=Ready pod -l app=booking`. That label also matches
the old Pod, which was deleted with `--wait=false` and is still terminating. A
timed-out wait ended the whole script with exit 1, no FAIL line and no summary;
it happened on the first attempt here, under host load. The check now waits on
`kubectl rollout status deployment/booking --timeout=120s` and records a pass or
fail. The rerun passed 149/149.

A first attempt at this pass was aborted and discarded: a variable-name clash
in the audit's own runner script skipped Stage 4's teardown, so Stage 5 started
on top of Stage 4's resources. Both were torn down to a clean cluster before
this rerun. No evidence from that attempt is used here.
