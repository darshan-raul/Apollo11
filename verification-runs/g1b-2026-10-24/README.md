---
title: "G1b — Launchpad, Ignition and Stage 1 re-verification (2026-10-24)"
description: "Live lifecycle evidence for Launchpad, Ignition and Stage 1 on Apollo11 97232fb."
---

# G1b — Launchpad, Ignition and Stage 1 (2026-10-24)

Code: Apollo11 `97232fb`. None of the three stages' code was touched by the
uncommitted G17 work running in parallel, which changes only Stages 5–7. Host:
6 CPUs, 16 GB, Docker 29.7.2, load average below 1 at the start. Kubernetes
v1.37.0 on a fresh three-node `kind-apollo11` cluster built from
`stages/ignition/kind-config.yaml`. Before recreating it, the earlier cluster
held only system namespaces (`ignition-precheck.txt`).

## Results

| Phase | Verify | Learner labs | Teardown / residue |
|---|---|---|---|
| Launchpad | **74 passed, 0 failed** (`launchpad-verify.log`) | `flight-db` stop: flight `/healthz` 200, `/readyz` 503, search and booking `/readyz` 503; start: all 200. `identity-db` container removed and recreated: users 2 → 2 (`launchpad-break-recover.log`) | `docker compose down --volumes`: the 3 owned volumes and all project containers are gone (`launchpad-residue.log`). Four `launchpad_{auth,catalog,circulation,fines}-*` volumes from the old library-era app predate this run and were left alone. |
| Ignition | **14 passed, 0 failed** (`ignition-verify.log`) | Kill httpd: same UID, restarts 0 → 1, HTTP "Apollo11 Ignition ready". Delete: `NotFound`. Reapply: new UID, HTTP restored (`ignition-break-recover.log`) | Pod deleted; cluster kept for Stage 1, as the docs instruct |
| Stage 1 | **167 passed, 0 failed** (`stage1-verify.log`) | Missing image tag: rollout status times out, new Pod `ErrImagePull`, two old Pods Ready, search `/readyz` 200. `rollout undo`: back to `apollo11/search:latest`, `/readyz` 200 (`stage1-break-recover.log`) | `teardown.sh`: namespace `NotFound`, 0 `apollo-airlines` objects (`stage1-residue.log`). Cluster kept for G1c. |

Totals for `AGENTS.md` (via G11): Launchpad 74, Ignition 14, Stage 1 167.

## Observation

`kubectl rollout undo` (kubectl v1.37.1) prints a warning that the rollback
does not update the `kubectl.kubernetes.io/last-applied-configuration`
annotation. The Stage 1 README does not mention it. Added to G23.

`.env` was generated from `.env.example` with random values for this run and
deleted afterwards.
