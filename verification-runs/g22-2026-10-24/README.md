---
title: "G22 — Stage 5 Helm release, rollback, test and comparison labs (2026-10-24)"
description: "Live evidence for the Stage 5 release lab, the helm test hook and the Helm vs Kustomize comparison lab."
---

# G22 — Stage 5 release, rollback, test and comparison labs (2026-10-24)

## What was added

- `stages/stage5/helm/apollo11/templates/tests/smoke-test.yaml`: a non-root,
  read-only busybox Pod run by `helm test`. It checks identity readiness,
  flight's seeded inventory and the frontend from inside the cluster.
- `stages/stage5/scripts/release-lab.sh`: inspect history → upgrade with a
  nonexistent image tag (`--wait --timeout 90s`) → assert the release is
  `failed`, new search Pods show an image-pull error, and the old Pod still
  serves → `helm rollback` → assert a new "Rollback to N" revision, the
  restored image and serving search → `helm test`.
- `stages/stage5/scripts/compare-lab.sh`: renders dev/prod with both tools,
  then makes the same change (3 `search` replicas in dev) with `helm --set`
  and a Kustomize `replicas:` overlay patch and checks they agree. No cluster
  needed; `test/ci.sh` now runs it.
- Stage 5 README section "Labs: break and recover a release", with Build →
  Inspect → Break → Recover → Explain.

## Evidence

| Run | Result | File |
|---|---|---|
| Helm/dev install | exit 0 | `apply.log` |
| `release-lab.sh` | **8 passed, 0 failed**: upgrade failed, status `failed`, image-pull error, old Pod served, revision 3 "Rollback to 1" deployed, image restored, search served, `helm test` passed (3 smoke checks) | `release-lab.log` |
| `verify.sh --mode helm` immediately after the lab | 173/174: the trusted HTTPS check for `search` through the Envoy Gateway returned **502** | `verify-after-lab.log` |
| Repeat install + lab, then wait | lab exit 0; about 5 minutes later all four HTTPS routes return 200 and `verify.sh` passes **174/174** | `rerun-*.log`, `rerun-edge-after-rollback.txt` |
| `compare-lab.sh` | 2 passed, 0 failed (also runs in `test/ci.sh`) | n/a |
| Teardown `--purge` (both runs) | no Apollo, Envoy or MetalLB namespaces | `teardown.log`, `rerun-teardown.log` |

The first 120 s of probing in `rerun-edge-after-rollback.txt` show `000`
because the probe used the wrong Secret name (`apollo-tls-secret`; Stage 5
uses `apollo-edge-tls`). That was a mistake in the probe, not a system
result. The correct probe followed.

## Observation for learners

Right after a rollback the edge can briefly return 502 for the rolled-back
service, while in-cluster calls already succeed: Envoy is still picking up the
new endpoints. The README tells learners to retry the edge check before
concluding that the rollback failed. How long that window lasts was not
measured precisely (under 5 minutes here).

## Not covered

ROADMAP 5.5 (promotion across dev/staging namespaces) is split out as G22b.
