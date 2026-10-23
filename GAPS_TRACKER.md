---
title: "Apollo11 Gap Tracker"
description: "The single backlog for the Apollo11 lab and apollo11-docs: evidence-backed tasks, dependencies, execution waves and an agent pickup protocol."
---

# Apollo11 Gap Tracker

This file is the only backlog for Apollo11 and apollo11-docs. Supporting reports
hold evidence, not tasks. It supersedes the open-item lists in
`AUDIT_GAPS_AND_EXPANSIONS.md`, `DOCS_IMPROVEMENT_REPORT.md`,
`verification-runs/GAP_CLOSURE.md` and the handoff files, all of which are
historical.

- **Origin:** full static review on 2026-10-19 at `1ac5c66` (G1–G16).
- **Latest audit:** 2026-10-23 at Apollo11 `5790cd9` and apollo11-docs
  `8362c51`. The phase-by-phase evidence, the checks run and the docs coverage
  map are in
  [`verification-runs/audit-2026-10-23/README.md`](verification-runs/audit-2026-10-23/README.md).

## Baseline at the 2026-10-23 audit

| Item | Value |
|---|---|
| Apollo11 local | `5790cd9`, clean before this audit |
| Apollo11 `origin/main` | `97232fb` (docs-only Stage 8 Reloader plan, PR #80). Pulled 2026-10-24; its G7 row edit is folded into G7/G7c below. |
| apollo11-docs local / origin | `8362c51` at audit; pulled to `b0838a3` (adds the Stage 8 Reloader page) on 2026-10-24. |
| Docs source pin | Apollo11 `f6211e6` |
| Hosted CI | **Failed on all 30 most recent runs (2026-06-17 → 2026-10-23)**, at the validation step. No release tags exist. |
| Static checks run | `test/generated.py --check`, `test/review` (20 tests), `shellcheck` over all stage scripts, docs `npm run typecheck` and `npm run build`: all pass |
| Not run | Clusters, Compose, image builds, Terraform, AWS, Go tests, hosted workflows (out of scope or tooling not installed) |

## Conventions

**Status:** `open`, `in-progress`, `done` (date + evidence), `dropped` (reason).
Blocked work stays `open` with its blocker named under **Gates**. Do not mark
`done` when the acceptance criteria require a live or hosted run that has not
happened.

**Priority:**

| | Meaning |
|---|---|
| P0 | Shown to block the working path, a serious correctness or security issue, or missing proof that invalidates a completion claim |
| P1 | Substantial correctness or learning gap on the required path (Launchpad → Stage 9) |
| P2 | Maintenance, reproducibility, lower-impact improvements |
| P3 | Optional enhancements and specializations (Stages 10–11) |

**Evidence labels:** **[code]** read in source, not run; **[static]** a local
static check passed; **[hosted]** read from GitHub; **[live-hist]** an earlier
live run under `verification-runs/`; **[unverified]** no evidence.

**Repos:** `A` = Apollo11, `D` = apollo11-docs.

## Agent pickup protocol

1. Run `git pull --ff-only` in both repos. Both were behind `origin/main` at the
   audit. Read this file, `AGENTS.md`, `ROADMAP.md`, and `README.md` for the docs
   repo.
2. Pick the highest-priority task in the earliest unfinished wave whose
   **Depends on** tasks are all `done` and whose **Gates** are cleared. Do not
   start a gated task without the named approval.
3. Read its evidence (file:line references, or the audit file) and confirm the
   finding still holds on the current HEAD. If it does not, record that and set
   the task to `dropped` or narrow it.
4. Set it to `in-progress` in the summary table and in its detail entry.
5. Work only inside the task's scope. If you find a new defect, add a new ID
   (next free number) rather than widening the task.
6. Run its verification. Save live evidence under
   `verification-runs/<id>-<YYYY-MM-DD>/` with a `README.md` summary, apply,
   verify, break/recover, teardown and residue logs.
7. Update the status and evidence in the table and the entry in the same
   session. Use `done` only when every acceptance criterion is met.
8. Do not commit, push, delete tracked files, publish images, run hosted
   workflows or touch AWS without explicit user approval. Local kind clusters
   named `apollo11*` are the authorized test surface; never delete other
   clusters or contexts.

## Execution waves

| Wave | Start when | Tasks (ready first) |
|---|---|---|
| 1 | Now | **G2a** (CI red; fix pushed, hosted result pending). Done 2026-10-24: G1b, G1c, G17, G10a, G24 |
| 2 | Now, in parallel with wave 1 | G18, G19, G20a, G20b, G20c, G21, G23, G3b, G8b, G13, G6b, G28, G8a, G29, G30 |
| 3 | After its dependencies in wave 1 | G15 (after G2a and push approval), G2b (after G2a), G1f (after G17, G21), G22 (after G17), G27 (after G17), G3a (after G17) |
| 4 | After wave 3 | G1d, G1e (after G1f); G6a (after G1b, G1c); G25a (after G18, G19); G25b (after G20a–c, G21); G26 (after G20c); G25c (after G17, G22, G26, G27, G15); G5 (after G17, G21, G6a); G11 (after G1b, G1c, G1f, G10a). G5 and G25c run last in this wave because they depend on G6a and G26. |
| 5 | After G17 and G1f | Stage 8: G7a → G7b → G7c → G7d (also needs G15) → G7e |
| 6 | After G7d and AWS approval | Stage 9: G8c → G8d → G8e |
| Gated, any time | When the user decides | G4, G10b deletions, G12 (deletions); G6c (`:latest` policy decision) |
| Optional | Any time | G9, G9a, G3c |

Blocked on external access or a decision: G2a (failed-job logs need GitHub auth
or the CI tool versions), G15 (push to `main`), G7d (signing identity in
GitHub), G8c (Terraform install), G8d (AWS account and budget), G29 (repo
settings), G4/G10b/G12 (approval for deletions), G6c (policy decision).

## Summary

| ID | Title | Repo | Phase | Pri | Status | Depends on | Wave |
|---|---|---|---|---|---|---|---|
| G1 | Live proof for current code across all implemented paths (parent) | A | Launchpad–Stage 7 | P0 | in-progress | G1b–G1f | — |
| G1a | promtool rule test and k6 cache off/on summaries | A | Stage 6–7 | P0 | done 2026-10-19 | — | — |
| G1b | Re-verify Launchpad, Ignition and Stage 1 on current code | A | Launchpad, Ignition, Stage 1 | P0 | done 2026-10-24 | — | 1 |
| G1c | Re-verify Stage 2 substages 1 and 2 | A | Stage 2 | P0 | done 2026-10-24 | — | 1 |
| G1d | Argo CD live pass for Stages 5–7 | A | Stage 5–7 | P1 | open | G1f | 4 |
| G1e | Helm/staging and live VPA for Stages 5–7 | A | Stage 5–7 | P2 | open | G1f | 4 |
| G1f | Stage 5–7 Helm and Kustomize dev re-run after code fixes | A | Stage 5–7 | P1 | open | G17, G21 | 3 |
| G2 | CI builds, tests and scans what it publishes (parent, reopened) | A | Stage 5 / CI | P0 | in-progress | G2a, G2b, G15 | — |
| G2a | Make the hosted CI validation job pass | A | CI | P0 | in-progress | — | 1 |
| G2b | Run the promtool SLO fixture in CI | A | CI, Stage 6–7 | P2 | open | G2a | 3 |
| G3 | Service tests (parent) | A | Stage 5–7 code | P2 | open | G3a–G3c | — |
| G3a | Identity unit tests (JWT, hashing, roles) | A | Stage 7 code | P2 | open | G17 | 3 |
| G3b | Flight seat and booking flow tests | A | Stage 7 code | P2 | open | — | 2 |
| G3c | Decide on `test/stageN_test.sh` wrappers | A | test | P3 | open | — | Optional |
| G4 | Remove legacy Stage 9–11 trees and tracked `dist/` | A | Stage 9–11, Launchpad | P2 | open | — | Gated |
| G5 | Snapshot drift check and copy policy | A | Cross-stage | P2 | open | G17, G21, G6a | 4 (last) |
| G6 | Supply-chain hygiene (parent) | A | Cross-stage | P2 | in-progress | G6a–G6c | — |
| G6a | Upgrade and pin Launchpad–Stage 4 base images | A | Launchpad–Stage 4 | P2 | open | G1b, G1c | 4 |
| G6b | Label teaching credentials everywhere | A | Cross-stage | P2 | open | — | 2 |
| G6c | Decide the `:latest` tag policy | A | Stage 5–7 | P2 | open | — | Gated |
| G7 | Stage 8 clean rebuild (parent) | A, D | Stage 8 | P1 | open | G7a–G7e | 5 |
| G7a | Stage 8.1 identity and workload baseline | A | Stage 8 | P1 | open | G17, G1f | 5 |
| G7b | Stage 8.2 Calico and enforced NetworkPolicy | A | Stage 8 | P1 | open | G7a | 5 |
| G7c | Stage 8.3 Vault, ESO and Reloader | A | Stage 8 | P1 | open | G7b | 5 |
| G7d | Stage 8.4 Kyverno, Trivy gate, Cosign | A | Stage 8 | P1 | open | G7c, G15 | 5 |
| G7e | Stage 8 docs walkthrough | D | Stage 8 | P1 | open | G7d | 5 |
| G8 | Stage 9 AWS capstone and EKS prototype (parent) | A, D | Stage 9, EKS | P1 | open | G8b–G8e | 6 |
| G8a | Launchpad verifier boundary | A | Launchpad | P3 | open | — | 2 |
| G8b | Make EKS prototype scripts fail safe | A | EKS | P2 | open | — | 2 |
| G8c | Stage 9 Terraform modules and cost inventory (static) | A | Stage 9 | P1 | open | G7d, G13 | 6 |
| G8d | Stage 9 real AWS lifecycle | A | Stage 9 | P1 | open | G8b, G8c | 6 |
| G8e | Stage 9 portability and gap analysis, docs | A, D | Stage 9 | P1 | open | G8d | 6 |
| G9 | Stage 10/11 optional missions (parent) | A, D | Stage 10–11 | P3 | in-progress | — | Optional |
| G9a | Make the Falco mission install reproducible | A | Stage 10 | P3 | open | — | Optional |
| G10 | One status source (parent) | A | Cross-cutting | P1 | open | G10a, G10b | — |
| G10a | Correct stale learner-facing status text | A | Stage 2–8, AGENTS | P1 | done 2026-10-24 | — | 1 |
| G10b | Mark or retire historical reports and handoffs | A | Cross-cutting | P2 | open | — | Gated |
| G11 | Shrink `AGENTS.md` and fix stale entries | A | Cross-cutting | P2 | open | G1b, G1c, G1f, G10a | 4 |
| G12 | Remove tracked editor and agent noise | A | Repo | P3 | open | — | Gated |
| G13 | Pin tools; state minimum resources | A | Toolchain | P2 | open | — | 2 |
| G14 | Docs repo aligned to `f6211e6` | D | All | P1 | done 2026-10-22 | — | — |
| G15 | Hosted CI green and first GHCR publication | A | Stage 5 / CI | P0 | open | G2a | 3 |
| G16 | Stage 7 scaling-lab spread flake | A | Stage 7 | P1 | done 2026-10-19 | — | — |
| G17 | Restore Stage 4 hardening in Stage 5–7 code | A | Stage 5–7 | P1 | done 2026-10-24 | — | 1 |
| G18 | Fix Stage 2 lab instructions and frontend expectations | A | Stage 2 | P1 | open | — | 2 |
| G19 | Correct Stage 3 storage teaching; add data-loss and Redis proofs | A | Stage 3 | P1 | open | — | 2 |
| G20 | Stage 4 ROADMAP migration (parent) | A | Stage 4 | P1 | open | G20a–G20c | — |
| G20a | Stage 4 probe and termination proofs | A | Stage 4 | P1 | open | — | 2 |
| G20b | Stage 4 resources, QoS, throttling, OOM, FailedScheduling | A | Stage 4 | P1 | open | — | 2 |
| G20c | Stage 4 placement and drain lab with outcome checks | A | Stage 4 | P1 | open | — | 2 |
| G21 | Make identity's graceful shutdown real | A | Stage 4–7 | P2 | open | — | 2 |
| G22 | Stage 5 Helm release, rollback, test and comparison labs | A | Stage 5 | P1 | open | G17 | 3 |
| G23 | Smooth Launchpad → Ignition → Stage 1 transitions | A | Launchpad–Stage 1 | P2 | open | — | 2 |
| G24 | Correct the docs status page | D | Status | P1 | done 2026-10-24 | — | 1 |
| G25 | Docs follow-ups to lab changes (parent) | D | Stage 2–7 | P2 | open | G25a–G25c | — |
| G25a | Docs for Stage 2/3 changes | D | Stage 2–3 | P2 | open | G18, G19 | 4 |
| G25b | Docs for Stage 4 changes | D | Stage 4 | P2 | open | G20a, G20b, G20c, G21 | 4 |
| G25c | Docs for Stage 5–7 changes and re-pin | D | Stage 5–7 | P2 | open | G17, G22, G26, G27, G15 | 4 (last) |
| G26 | Reorder Stage 7 README; drop duplicate "new" claims | A | Stage 7 | P2 | open | G20c | 4 |
| G27 | Live-verify Stage 6's ordered signal path | A | Stage 6 | P1 | open | G17 | 3 |
| G28 | Decide and prove single-node kind support | A | Ignition–Stage 7 | P2 | open | — | 2 |
| G29 | Enable or remove the CodeQL workflow | A | CI | P3 | open | — | 2 |
| G30 | Docs toolkit map lists tools the course never covers | D | Home, index | P2 | open | — | 2 |

Dependency check: every ID in **Depends on** exists in this table, and the
graph has no cycles. Longest chain: G17 → G1f → G7a → G7b → G7c → G7d → G8c →
G8d → G8e.

## Already closed (do not redo)

Stage 5–7 kube-context guards (`apollo_context_guard` in every Stage 5–7
apply, verify and teardown script, confirmed 2026-10-23); EBS sweep ownership
filter (`stages/eks/scripts/ebs-sweep.sh:23-27`, confirmed); missing
`helm_release` reference in `stages/eks/terraform`; `preStop` and topology
spread in the Stage 5–7 charts; `stages/stage7/k6/search.js`; legacy
`stage2/set*` directories; `30088` port references; HTTPS listener on the Envoy
Gateway; Stage 2 inert NetworkPolicy manifests removed (none remain under
`stages/stage2`).

## Task details

Each entry lists: finding and evidence, scope and starting files, deliverables,
acceptance criteria, verification, where to record evidence, and gates.

### G1 — Live proof for current code (parent) · A · P0 · in-progress

Original acceptance: fresh apply → inspect → break → recover → teardown for
every implemented path, totals recorded, `AGENTS.md` and READMEs updated, zero
namespace/CRD residue. Closes when G1b–G1f are done and G11 has recorded the
counts.

Historical evidence (preserved): S1 2026-10-19, Stage 2 sub 5/3/4, Stage 3 and
Stage 4 apply, verify and teardown passed (`verification-runs/s1-2026-10-19/`).
S2 the same day: Stage 5/6/7 Helm and Kustomize dev passed (174/163, 212/201,
227/216) with clean purges (`verification-runs/s2-2026-10-19/`). Closure pass:
Argo CD Stage 5 74/74; Stage 6/7 79/88 and 80/88 under host load (not a pass);
Helm/staging not re-run. Fix pass 2026-10-22 (`verification-runs/fix-2026-10-22/`):
Stage 5/6/7 Helm and Kustomize dev re-run on upgraded images, 174/163, 212/201,
227/216, purges clean; Stage 6/7 trace-test and observability-lab pass.

Gaps the 2026-10-23 audit found in that evidence: Launchpad, Ignition and Stage 1
have no run since their code or verifiers changed (G1b). Stage 2 sub 1/2 have no
October log (G1c). Argo CD never passed for Stage 6/7 (G1d). Staging and live
VPA date from 2026-08-25 (G1e). G17 and G21 will change Stage 5–7 code again (G1f).

### G1b — Re-verify Launchpad, Ignition and Stage 1 · A · P0 · done 2026-10-24

**Evidence (2026-10-24, `97232fb`):** Launchpad 74/74 with the outage and persistence labs and a clean `down --volumes`; Ignition 14/14 on a fresh three-node cluster with crash and delete recovery; Stage 1 167/167 with failed rollout and `rollout undo`, namespace gone after teardown (`verification-runs/g1b-2026-10-24/README.md`). The `rollout undo` warning found here is added to G23.

- **Why P0:** `AGENTS.md:916-918` mark all three "Complete" from 2026-09-05 runs,
  but `1ac5c66` (2026-10-09) changed Launchpad and Stage 1 service code,
  `flight/init.sql`, `docker-compose.yml` and `scripts/verify.sh`, and `f6211e6`
  changed `stages/ignition/scripts/verify.sh` and `stages/stage1/scripts/build-images.sh`
  [code]. ROADMAP trust policy rule 6 forbids completion claims from historic counts.
- **Scope:** run the three lifecycles. Fix only defects that the run exposes, in
  the stage that exposes them. Starting files: `stages/launchpad/scripts/verify.sh`,
  `stages/ignition/scripts/verify.sh`, `stages/stage1/scripts/{apply,verify,teardown}.sh`.
- **Deliverables:** one evidence directory with logs and a summary of totals.
- **Acceptance:**
  1. Launchpad: `docker compose up --build --wait -d` reports 10 healthy;
     `scripts/verify.sh` ends with 0 failed (record the total); README step 5
     (stop `flight-db` → flight `/readyz` 503, `/healthz` 200 → start →
     200) and step 6 (identity user count unchanged across container removal)
     are captured; after `docker compose down --volumes`, `docker volume ls`
     shows no `launchpad_` volumes.
  2. Ignition: fresh three-node `kind-apollo11`; `verify.sh` 0 failed; the
     crash (same UID, restarts +1) and delete (NotFound, then new UID) steps
     are captured with an HTTP response after each recovery.
  3. Stage 1: `apply.sh`, `verify.sh` 0 failed, the README's failed-rollout and
     `rollout undo` steps captured, `teardown.sh`, then
     `kubectl get ns apollo-airlines` returns NotFound.
- **Verify:** the commands above, from the repo root.
- **Evidence:** `verification-runs/g1b-<date>/README.md`; update G1 and this row.
- **Gates:** Docker daemon and a local kind cluster. Uncertainty: none.

### G1c — Re-verify Stage 2 substages 1 and 2 · A · P0 · done 2026-10-24

**Evidence (2026-10-24, `97232fb`):** substage 1 46/46 with the selector break and recovery; substage 2 48/48 with the `targetPort` break and recovery; teardown left no Stage 2 namespace, CRD or ClusterRole (`verification-runs/g1c-2026-10-24/README.md`). Two findings were added to G18.

- **Why P0:** `AGENTS.md:919` lists 46/46 and 48/48 for sub 1/2, but
  `verification-runs/s1-2026-10-19/` holds logs for sub 3/4/5 only. The sub 1/2
  "breaks run" note in the old G1 row has no log [live-hist gap]. `f6211e6`
  changed `stages/stage2/scripts/{apply,verify,teardown}.sh`.
- **Scope:** `stages/stage2/scripts/apply.sh --substage 1` and `--substage 2`
  on a fresh cluster, with the substage README break/recover.
- **Acceptance:** for each substage, `verify.sh` 0 failed (record the total);
  sub 1: an identity selector break shows `kubectl get endpoints identity` empty,
  and the restore shows it populated plus a `curl-client` HTTP 200 by FQDN;
  sub 2: `targetPort: 9999` gives a connection failure on `localhost:30083`,
  the restore gives 200; `teardown.sh` leaves no Stage 2 namespace, Gateway
  API/Envoy/MetalLB CRD or ClusterRole (it already fails if any remain).
- **Evidence:** `verification-runs/g1c-<date>/`.
- **Gates:** local kind. Uncertainty: none.

### G1d — Argo CD live pass for Stages 5–7 · A · P1 · open

- **Finding:** Stage 6 79/88 and Stage 7 80/88 on 2026-10-19 with identity
  startup-probe failures (`verification-runs/s2-2026-10-19/argocd/summary.txt`).
  The `stage7-rerun/` directory has no verify log. A likely cause, identity
  stalling at its 128Mi limit, was fixed on 2026-10-22
  (`verification-runs/fix-2026-10-22/README.md`) [unverified for Argo]. Stage 5's
  74/74 predates the 2026-10-22 image upgrade.
- **Scope:** `stages/stage{5,6,7}/argocd/{install.sh,scripts/bootstrap.sh,scripts/verify.sh,scripts/teardown.sh}`
  using the existing local Git fixture. No push.
- **Acceptance:** per stage, `argocd/scripts/verify.sh` ends 0 failed, including
  the replica-drift self-heal; `uptime` load average below the core count is
  recorded at start and end; `teardown.sh --purge` leaves no Argo CD or tenant
  namespace or CRD.
- **Evidence:** `verification-runs/g1d-<date>/`. Then fix the Stage 6 and
  Stage 7 rows of `AGENTS.md` (through G11).
- **Gates:** quiet host (G13 records the minimum).

### G1e — Helm/staging and live VPA for Stages 5–7 · A · P2 · open

- **Finding:** Stage 7 README cites Helm/staging 211/211 with live VPA from
  2026-08-25, before the 2026-10-22 image upgrade. Staging was not re-run for
  any stage (`fix-2026-10-22/README.md`, "Not covered").
- **Acceptance:** `scripts/apply.sh --mode helm --env staging` then
  `verify.sh --mode helm` 0 failed for Stages 5, 6 and 7; for Stage 7,
  `kubectl describe vpa` shows a populated `Recommendation` for `search` and
  `updateMode: "Off"`; `teardown.sh --purge` clean.
- **Evidence:** `verification-runs/g1e-<date>/`.

### G1f — Stage 5–7 dev re-run after code fixes · A · P1 · open

- **Finding:** G17 and G21 change Stage 5–7 images. The 2026-10-22 evidence
  will no longer describe the shipped code.
- **Acceptance:** Helm/dev and Kustomize/dev `verify.sh` 0 failed for Stages
  5–7; Stage 6/7 `trace-test.sh` and `observability-lab.sh` pass; Stage 7
  `scaling-lab.sh run` passes; purges leave only the built-in
  `system:monitoring` objects; one `docker run --rm --entrypoint id` per image
  shows a non-zero UID.
- **Evidence:** `verification-runs/g1f-<date>/`.

### G1a — promtool rule test and k6 summaries · A · P0 · done 2026-10-19

promtool 3.15.0 installed with `mise use -g promtool` (2026-10-19); `promtool
test rules` passes on the live rules; k6 cache off/on summaries saved in
`verification-runs/s2-2026-10-19/`. Not yet a CI gate: see G2b.

### G2 — CI builds, tests and scans what it publishes (parent) · A · P0 · in-progress (reopened 2026-10-23)

Original acceptance: CI builds and tests the code each published tag claims to
ship; runs `test/review`, `go test` for search, Helm lint and render for Stages
5–7, `shellcheck` over all stage scripts, and a Trivy image scan.

Historical evidence (preserved): CI matrix across Stages 5, 6, 7 and all six
services; Trivy gate pinned by commit (trivy-action v0.36.0, Trivy v0.70.0);
the exact scanned image is published on push or tag. The first config failed the
gate (search: 2 CRITICAL, 54 HIGH). After the G6 upgrade, all 18 images pass
locally (`verification-runs/fix-2026-10-22/trivy/`) and `test/ci.sh` passes
(`verification-runs/fix-2026-10-22/ci-local.log`).

**Why reopened:** the hosted run of the closing commit `f6211e6`, and of every
later push, fails at "Validate all maintained charts, overlays, scripts, and
tests" (runs 39684523245, 39821233584, 39985772897) [hosted]. The configuration
exists but has never passed where it runs. Closes when G2a, G2b and G15 are done.

### G2a — Make the hosted CI validation job pass · A · P0 · in-progress

**Progress (2026-10-24):** root cause reproduced. The committed `generated.yaml` files are Helm 4 renders, and CI's Helm 3.16.2 adds no blank line between documents, so `test/generated.py --check` reports them stale in under a second, matching the 0 s hosted step. Fix: CI pins Helm v4.3.1, kubectl v1.37.1 and Trivy v0.75.0 (the locally verified versions), and `test/ci.sh` prints versions and refuses Helm 3. `bash test/ci.sh` passes locally (`verification-runs/g2a-2026-10-24/README.md`). Remaining: the hosted run must go green.

- **Finding:** all 30 recent runs of `.github/workflows/main.yml` fail; build and
  publish never run. Locally, `test/generated.py --check`, `test/review` and
  `shellcheck` pass [static]. CI pins Helm v3.16.2 and kubectl v1.30.0
  (`main.yml:33-40`), while the passing local runs used Helm v4.3.1 and kubectl
  v1.37.1. `test/generated.py` compares `helm template` output byte for byte
  against committed files rendered with Helm 4, which makes it the most likely
  cause [unverified]. CI's Trivy v0.70.0 also differs from the local 0.75.0.
- **Scope:** `.github/workflows/main.yml`, `test/ci.sh`, `test/generated.py`.
- **Deliverables:** the root cause, quoted from the failing log; a fix; CI and
  local verification on the same Helm, kubectl and Trivy versions (pin CI to
  the verified versions, or have `test/ci.sh` print and check versions); a short
  note in `stages/stage5/README.md` on which versions CI uses.
- **Acceptance:** the failing log line is recorded; `bash test/ci.sh` passes
  locally with exactly the versions the workflow pins; the hosted run is green
  (tracked and evidenced in G15).
- **Verify:** `gh run view 39985772897 --repo darshan-raul/Apollo11 --log-failed`
  (the user can run it with `! gh ...` once `gh` is authenticated), or open
  <https://github.com/darshan-raul/Apollo11/actions/runs/39985772897>.
- **Evidence:** `verification-runs/g2a-<date>/README.md`.
- **Gates:** reading the logs needs GitHub authentication; installing `gh` or
  extra Helm/kubectl versions needs user approval. Uncertainty: root cause
  unconfirmed.

### G2b — Run the promtool SLO fixture in CI · A · P2 · open

- **Finding:** `test/stage6_slo_rules_test.yaml` exists and passed by hand
  (G1a), but neither `test/ci.sh` nor the workflow runs `promtool`;
  `test/review/README.md:18-19` says it must be run separately.
- **Deliverables:** a `test/ci.sh` step that renders the Stage 6 and Stage 7
  PrometheusRule, extracts `spec` to a temporary `rules.yaml`, and runs
  `promtool test rules`; install promtool in the workflow at a pinned version.
- **Acceptance:** the step passes; deliberately breaking one SLO expression makes
  it fail (log both).
- **Depends on:** G2a.

### G15 — Hosted CI green and first GHCR publication · A · P0 · open

- **Why P0:** the Stage 5 learning path claims CI/GHCR delivery
  (ROADMAP Stage 5.3) and `values-prod.yaml:7-8` pins
  `ghcr.io/darshan-raul/apollo11/stage5` at `v1.0.0`, but CI has never passed and
  no tag exists (`GET /repos/darshan-raul/Apollo11/tags` returns `[]`) [hosted].
  The 2026-10-19 note "never observed" is outdated: the runs were observed, and
  they fail.
- **Acceptance:** one push run on `main` where lint, all 18 build jobs and all
  18 publish jobs succeed; 18 packages exist under
  `ghcr.io/darshan-raul/apollo11/stage{5,6,7}/<service>` tagged
  `sha-<commit>`; an anonymous `docker pull` of one of them succeeds, or package
  visibility is documented. Whether to create release tag `v1.0.0` is decided
  separately; until it exists, G10a wording must say prod images are not
  published.
- **Evidence:** `verification-runs/g15-<date>/` with run URL, jobs JSON and pull
  output.
- **Gates:** a push to `main` (user approval). Depends on G2a.

### G3 — Service tests (parent) · A · P2 · open

Original criteria: unit tests for auth/JWT, booking flow and seat logic in at
least identity, flight and booking; run in CI; `test/stageN_test.sh` wrappers
do real work or are removed. Priority lowered from P1: no learner path breaks
without these tests; they guard against regressions across seven code copies.
Today only `stages/stage7/code/search` has tests (`cache_test.go`,
`handler_test.go`); `test/ci.sh:16-18` runs `go test` for Stages 5–7 and finds
none elsewhere.

### G3a — Identity unit tests · A · P2 · open

- **Scope:** `stages/stage7/code/identity/main.py`, plus copies to Stages 5–6
  per the G5 policy. Depends on G17, which may change the hashing library.
- **Acceptance:** pytest cases cover issuing a JWT, rejecting a token signed
  with another secret, rejecting an expired token, role enforcement on an ADMIN
  route, and login failure for a bad password, with the DB stubbed; `test/ci.sh`
  and the workflow run them; each fails when the guarded behavior is broken by
  hand.

### G3b — Flight seat and booking flow tests · A · P2 · open

- **Scope:** `stages/stage7/code/{flight,booking}/main.go`.
- **Acceptance:** Go tests cover seat decrement never going below zero, restore
  on cancel, the booking service minting a 5-minute `SERVICE` JWT for internal
  seat calls, and compensation when the seat call fails; `go test -race ./...`
  passes in `test/ci.sh`.

### G3c — Decide on `test/stageN_test.sh` wrappers · A · P3 · open

- **Finding:** `test/stage{1..7}_test.sh` are 8-line `exec` aliases for each
  stage's `verify.sh`.
- **Acceptance:** either `test/review/README.md` documents them as aliases, or
  they are removed (removal needs approval).

### G4 — Remove legacy Stage 9–11 trees and tracked `dist/` · A · P2 · open

- **Finding (confirmed 2026-10-23):** `stages/stage{9,10,11}/code` hold the
  library-era `auth`, `catalog`, `circulation`, `fines` services, plus `k8s/`
  (and `terraform/` in Stage 9). 12 `dist/` files are tracked despite
  `.gitignore` `**/dist/` (3 each in `launchpad`, `stage9`, `stage10`,
  `stage11` `code/frontend/dist/`). Stage 8 is now README-only, so that part of
  the original row is resolved. Priority lowered from P1: each README already
  says "do not apply".
- **Acceptance:** `git ls-files | grep -c /dist/` returns 0; `git ls-files stages/stage{9,10,11}`
  lists only READMEs and `stage10/missions/**`; `test/ci.sh` still passes;
  READMEs keep their planned status; `ROADMAP.md` unchanged.
- **Gates:** explicit user approval to delete tracked files.

### G5 — Snapshot drift check and copy policy · A · P2 · open

- **Finding:** the 69 MB question is resolved: `launchpad/code` (69 MB) and each
  of Stages 9–11 (73 MB) are ignored `node_modules`, not tracked content
  [static]. The drift itself is real: Stage 4 → 5 differs in 30 files (audit
  section 4), and is handled in G17. `generate-certs.sh`, `context.sh` and
  `verify-tls.sh` are still copied per stage.
- **Deliverables:** a drift script (for example `test/snapshot_drift.py`) with an
  allowlist of intended per-stage differences, run from `test/ci.sh`; a written
  copy-versus-shared-script policy in `AGENTS.md`.
- **Acceptance:** the script passes on the tree; introducing an unlisted change in
  `stages/stage5/code/booking/main.go` makes it fail; the policy is documented.
- **Depends on:** G17, G21, G6a, so the allowlist records only intended
  differences.

### G6 — Supply-chain hygiene (parent) · A · P2 · in-progress

Original criteria: supported Go across services and Dockerfiles with tests
passing; base images pinned by version; teaching Secrets labelled in each
README; a decision on `:latest`. Priority lowered from P1: these are local
teaching images, and the Stage 5–7 images that CI publishes are done.

Historical evidence (preserved): 2026-10-22, Stages 5–7 only: Go 1.27.3
builders with module deps upgraded (`go 1.26.0`), pinned `alpine:3.24.2`,
`nginx:1.30.6-alpine3.24`, `node:22.23.4-alpine3.24`,
`python:3.12.15-slim-trixie`, runtime `apk upgrade`; identity on FastAPI 0.159 /
Starlette 1.9; all 18 images pass Trivy and live lifecycles
(`verification-runs/fix-2026-10-22/`).

### G6a — Upgrade and pin Launchpad–Stage 4 base images · A · P2 · open

- **Finding:** `stages/{launchpad,stage1,stage2,stage3,stage4}/code/*/Dockerfile`
  use `golang:1.22-alpine`, `alpine:3.19`, `node:20-alpine`, unpinned
  `nginx:alpine` and `python:3.12-slim` [code].
- **Acceptance:** `grep -rn "golang:1.22\|alpine:3.19\|node:20\|nginx:alpine$\|python:3.12-slim$" stages/{launchpad,stage1,stage2,stage3,stage4}/code/*/Dockerfile`
  returns nothing; `trivy image --ignore-unfixed --severity CRITICAL,HIGH` passes
  for every rebuilt image; the G1b and G1c verifiers and the Stage 3 and Stage 4
  verifiers pass again on the new images.
- **Depends on:** G1b, G1c (prove the current baseline first so regressions
  can be attributed).

### G6b — Label teaching credentials · A · P2 · open

- **Finding:** plaintext teaching values exist in `stages/launchpad/.env.example`,
  every stage's Secret manifests and chart templates, Grafana
  `admin`/`apollo-admin` (`stages/stage6/README.md`), and the Argo CD admin
  bootstrap. Not all are labelled.
- **Acceptance:** every teaching Secret carries the label
  `apollo11.io/teaching-only: "true"` or a header comment; each stage README has
  a "Teaching credentials" note that points to Stage 8 (G7c) for real secret
  delivery; a grep listing of the Secret files is recorded.

### G6c — Decide the `:latest` tag policy · A · P2 · open

- **Finding:** dev and staging values, overlays, and the Argo CD dev/staging
  Applications use `:latest` (`AGENTS.md:673-675`).
- **Deliverable:** a recorded decision (keep for local kind with a stated reason,
  or move to `sha-` tags once G15 publishes), then the matching edits.
- **Gates:** user decision.

### G7 — Stage 8 clean rebuild (parent) · A, D · P1 · open

Built from the verified Stage 7 Helm baseline under the learner contract, one
substage at a time, each with a live lifecycle (Build → Inspect → Break →
Recover → Explain). Helm only; no parallel Kustomize platform (ROADMAP Stage 5
rule). The remote commit `97232fb` adds Stakater Reloader to substage 3 with a
configuration-change rollout policy; read `ROADMAP.md` on `origin/main` before
starting G7c. `stages/stage8/README.md` calls Stage 7 "the hardened baseline",
which is not true until G17 lands.

### G7a — Stage 8.1 identity and workload baseline · A · P1 · open

- **Scope:** new `stages/stage8/` snapshot from Stage 7 Helm: RBAC, Pod Security
  Admission `restricted`, dedicated ServiceAccounts with automount off where
  unused, `runAsNonRoot`, seccomp `RuntimeDefault`, `drop: [ALL]`,
  `readOnlyRootFilesystem`.
- **Acceptance:** the app namespaces carry `pod-security.kubernetes.io/enforce: restricted`;
  a deliberately privileged Pod is rejected with the PSA message (break) and a
  compliant one is admitted (recover); `kubectl auth can-i` output shows each SA's
  least privilege; all workloads Ready and the booking workflow passes;
  `teardown.sh` leaves no residue; live evidence recorded.
- **Depends on:** G17 (images must run non-root), G1f.

### G7b — Stage 8.2 Calico and enforced NetworkPolicy · A · P1 · open

- **Acceptance:** a kind config with `disableDefaultCNI: true` plus pinned
  Calico; default-deny makes a named flow fail (for example booking →
  identity-db times out); the allowlist restores it; the booking workflow passes
  under policy; a non-allowed flow stays denied; teardown clean.
- **Depends on:** G7a.

### G7c — Stage 8.3 Vault, ESO and Reloader · A · P1 · open

- **Acceptance (per ROADMAP on `97232fb`):** pinned Vault, External Secrets
  Operator and Reloader v1.4.22 (opt-in, named annotations, Postgres
  StatefulSets not opted in); rotating `JWT_SECRET` in Vault → ESO sync →
  Reloader rollout, after which a pre-rotation token is rejected and a fresh
  login succeeds; stopping Vault shows an ESO sync error while the existing
  Secret keeps working; restoring Vault resyncs; teardown clean.
- **Depends on:** G7b.

### G7d — Stage 8.4 Kyverno, Trivy gate and Cosign · A · P1 · open

- **Acceptance:** Kyverno audit mode reports violations, then enforce mode
  rejects an unsigned image with a policy message; an image signed in CI is
  admitted; the Trivy gate failing blocks publication (reuse G2).
- **Depends on:** G7c, G15. **Gates:** a signing identity (keyless OIDC or key)
  in GitHub needs user approval.

### G7e — Stage 8 docs walkthrough · D · P1 · open

- **Scope:** replace the planned `docs/stage-8.md` with a walkthrough and update
  `docs/status.md`, keeping the concept chapters. Pin to the Apollo11 commit
  carrying G7a–G7d evidence.
- **Acceptance:** every command is source-checked against that pin; live results
  cite the G7 evidence directories; `npm run typecheck`, `npm run build` and
  `git diff --check` pass.
- **Depends on:** G7d.

### G8 — Stage 9 AWS capstone and EKS prototype (parent) · A, D · P1 · open

Original row: add an account and context allowlist to `stages/eks/scripts/*`
now; rebuild on the Stage 7 platform only after explicit authorization for a
real AWS lifecycle with zero owned residue. Priority raised from P2 because
Stage 9 is on the required path. It stays blocked behind Stage 8 and AWS
approval.

### G8a — Launchpad verifier boundary · A · P3 · open

- **Finding:** `stages/launchpad/scripts/verify.sh` checks for the `docker`
  binary but not daemon reachability or the Docker context. Its actions are
  bounded: it targets the Compose file explicitly (`-f`) and creates and cancels
  one booking. Priority lowered from P2.
- **Acceptance:** the verifier fails fast with a clear message when `docker info`
  fails and prints `docker context show`; the README states why no stronger
  guard is needed.

### G8b — Make EKS prototype scripts fail safe · A · P2 · open

- **Finding:** `stages/eks/scripts/apply-workloads.sh:105` applies
  `stages/stage3/k8s/serviceaccounts/`, which does not exist (ServiceAccounts are
  in `k8s/config/`), so the script aborts at step 3. No script checks the AWS
  account ID. `up.sh:57` runs `aws eks update-kubeconfig`, which silently
  switches the current context, and `apply-workloads.sh` then uses whatever
  context is current [code].
- **Deliverables:** an account-ID allowlist (`APOLLO11_AWS_ACCOUNT`) checked
  against `aws sts get-caller-identity`; an explicit context or private
  `KUBECONFIG` for every `kubectl` and `helm` call; the path fixed, or the
  script refusing to run with a "prototype" message.
- **Acceptance:** new tests in `test/review/test_safety.py` with fake `aws` and
  `kubectl` prove refusal on a wrong account and a wrong context; shellcheck
  passes; no real AWS call.

### G8c — Stage 9 Terraform modules and cost inventory (static) · A · P1 · open

- **Acceptance:** incremental modules covering ROADMAP Stage 9 items 1–5; a
  billable-resource inventory with estimated hourly and monthly cost;
  `terraform fmt -check`, `terraform validate` and a pinned `tflint` pass per
  module; a design note maps every ROADMAP Stage 9 item to a module or lab step.
  No `apply`.
- **Depends on:** G7d (hardened baseline), G13 (Terraform pin). **Gates:**
  installing Terraform.

### G8d — Stage 9 real AWS lifecycle · A · P1 · open

- **Acceptance:** apply → deploy the hardened Helm snapshot → DNS, cert-manager
  TLS → Pod and Cluster Autoscaler scaling → node drain and replacement →
  controlled Kubernetes upgrade → Velero backup and restore with application
  behavior proven → destroy → an ownership-scoped residue and cost audit showing
  zero owned resources.
- **Depends on:** G8b, G8c. **Gates:** explicit AWS authorization, a named
  account and a budget.

### G8e — Stage 9 portability and gap analysis, docs · A, D · P1 · open

- **Acceptance:** an EKS → GKE portability analysis and a production gap analysis
  (database HA, regional resilience, RPO/RTO, capacity, security, ownership) in
  `stages/stage9/`; `docs/stage-9.md`, `docs/eks.md` and `docs/status.md` updated
  from G8d evidence; docs checks pass.
- **Depends on:** G8d.

### G9 — Stage 10/11 optional missions (parent) · A, D · P3 · in-progress

Each mission is an independent lab with its own baseline, experiment, restore
and cleanup. Done: CloudNativePG and Falco, verified live 2026-10-22
(`verification-runs/fix-2026-10-22/cnpg-*`, `falco-*`), each in its own kind
cluster with a private kubeconfig. Remaining Stage 10: Linkerd, Argo Rollouts,
ephemeral-container debugging, Kubeshark, Chaos Mesh, advanced DR (after the
Stage 9 Velero lab). Remaining Stage 11: CRD/operator, KEDA, k3s, Backstage,
Kubecost, Cluster API. When you start a mission, give it the next free child ID
(G9b, G9c, …) with full task fields.

### G9a — Make the Falco mission install reproducible · A · P3 · open

- **Finding:** `stages/stage10/missions/falco/apply.sh` fetches the chart from
  GitHub release assets at install time; three of four attempts timed out
  (`verification-runs/fix-2026-10-22/falco-apply-attempt*-network-timeout.log`).
- **Acceptance:** the chart is pinned and vendored offline (as Envoy, MetalLB and
  Argo CD are), or `apply.sh` retries with a bounded backoff and a clear
  message; one clean apply → verify → teardown is recorded.

### G10 — One status source (parent) · A · P1 · open

Original criteria: one status source (this tracker plus `AGENTS.md`); handoff
files merged or removed; stale "uncommitted" language in `GAP_CLOSURE.md`
updated; stale audit items marked superseded. Split into G10a (learner-facing,
P1) and G10b (maintainer history, P2).

### G10a — Correct stale learner-facing status text · A · P1 · done 2026-10-24

**Evidence (2026-10-24):** the Stage 2–7 README banners now cite their evidence directories; Stage 5 counts are 174/163 and every CI/GHCR claim in Stage 5–7 and `AGENTS.md` says hosted runs fail and nothing is published; the `AGENTS.md` verification section points to this tracker; the Stage 8 README names the non-root and G1f prerequisites. `grep -rn "working tree" stages/*/README.md AGENTS.md` returns nothing.

- **Finding [code]:**
  - `stages/stage{2,3,4,5,6,7}/README.md` open with "the context, TLS, and
    contract fixes in this working tree require a fresh runtime lifecycle".
    Stages 2–7 were re-run on 2026-10-19 and 2026-10-22.
  - `stages/stage5/README.md:24` gives verify targets of 153/142 against the
    recorded 174/163; line 26 dates the 174/174 run 2026-08-22; lines 29-30 and
    386-388 say the hosted run "occur[s] on the next push/tag", but the hosted
    runs exist and fail (G2a, G15).
  - `stages/stage6/README.md:24-25` says hosted CI and Argo "require a push".
  - `AGENTS.md:48-54` "Verification status after the October gap fixes" says the
    working tree is unverified.
  - `stages/stage8/README.md` calls Stage 7 "hardened" (see G17).
- **Acceptance:** `grep -rn "working tree" stages/*/README.md AGENTS.md` returns
  nothing; each Stage 2–7 README status block cites its latest evidence directory
  and date; every CI/GHCR statement matches the current G15 state; the Stage 8
  README notes the non-root prerequisite until G17 is done.
- **Gates:** none. Uncertainty: none.

### G10b — Mark or retire historical reports and handoffs · A · P2 · open

- **Scope:** `handoff.md` (2026-09-05), `.handoff.md`, `stages/stage7/.handoff.md`,
  `AUDIT_GAPS_AND_EXPANSIONS.md`, `DOCS_IMPROVEMENT_REPORT.md`,
  `verification-runs/GAP_CLOSURE.md` ("All source changes are uncommitted"),
  `verification-runs/DOCS_HANDS_ON_LEARNING_REVIEW.md`,
  `verification-runs/LEARNER_FLOW_LAB_CROSSCHECK.md`,
  `verification-runs/apollo11-gap-fixes.patch`, `verification-runs/apollo11-docs-gap-fixes.patch`
  (the docs alignment record says not to apply the latter).
- **Acceptance:** every listed file starts with a one-line historical banner
  linking this tracker, or is moved or removed with approval; `AGENTS.md` names
  only this tracker and itself as status sources.
- **Gates:** approval for moving or deleting tracked files. Banners need none.

### G11 — Shrink `AGENTS.md` and fix stale entries · A · P2 · open

- **Stale entries found 2026-10-23 [code]:** Launchpad 73 (`:245`) vs 74
  (`:916`) checks; Stage 3 verifier "68 checks" (`:439`); Stage 5 "153 Helm / 142
  Kustomize" (`:655`); Stage 7 search "softly prefers" (`:727`; the spread is now
  `DoNotSchedule` + `Honor`); Stage 2 "NetworkPolicies: manifests provided for
  reference" (`:353`; none exist); Stage 5 "Code changes vs stage4: None"
  (false, G17); the Stage 10 summary omits CNPG and Falco; the mise tool list;
  the code-evolution row "stage7: All Go services graceful shutdown fully
  implemented".
- **Acceptance:** `AGENTS.md` ≤ ~300 lines, with per-stage detail moved into the
  stage READMEs; every count equals the latest evidence summary; none of the
  entries above remain.
- **Depends on:** G1b, G1c, G1f, G10a.

### G12 — Remove tracked editor and agent noise · A · P3 · open

- **Scope corrected 2026-10-23:** tracked are `.hermes/plans/*` (3 files) and
  `.vscode/settings.json`. `.devbox` does not exist; `.agents` and `.codex` are
  empty untracked directories, which Git cannot track.
- **Acceptance:** those four files are removed or ignored; `git ls-files .hermes .vscode`
  returns nothing.
- **Gates:** approval.

### G13 — Pin tools; state minimum resources · A · P2 · open

- **Finding:** every tool in `mise.toml` is `latest`. CI uses different versions
  from the local verified runs (see G2a). `k3d` and `minikube` are installed
  though no lab uses them, against the file's own rule ("Add a tool only when the
  lab that needs it is implemented"). S2 notes that labs flake when load average
  is far above the core count; the 2026-10-22 passes ran on 6 cores and 16 GB.
- **Acceptance:** no `latest` in `mise.toml`; versions match those recorded in the
  latest passing evidence and in CI; `./prep.sh --verify` passes; the README and
  docs `labs/setup.md` state minimum CPU and RAM for Stages 6–7 and the
  quiet-host requirement; k3d and minikube removed or justified.

### G14 — Docs repo aligned to `f6211e6` · D · P1 · done 2026-10-22

Audited docs base `aada9b0` plus the existing storage edits; aligned active pages
directly to code `f6211e6` (the last five commits). The historical patch targets
a superseded page structure; a reverse-apply check cannot establish application
history, so it was not applied blindly. `npm run typecheck`, `npm run build` and
`git diff --check` pass; 94 pinned source paths resolve locally. Existing edits
preserved. Review mapping: sibling `apollo11-docs/maintenance/repo-alignment-2026-10-22.md`;
docs alignment commit `4c36bfe` on docs main (integrated with `254a191`);
typecheck and build repeated after integration.

Reconfirmed 2026-10-23: typecheck and build pass at `8362c51`; the
planned-stage status language is accurate. The specific errors found are in
G24 and G25. Do not open another general alignment task.

### G16 — Stage 7 scaling-lab spread flake · A · P1 · done 2026-10-19

Spread changed to `DoNotSchedule`; 10/10 passes
(`verification-runs/s2-2026-10-19/g16/`). Follow-up 2026-10-22: the k6 capacity
run showed a third replica Pending, because the default `nodeTaintsPolicy:
Ignore` counted the tainted control plane as an empty domain. Added
`nodeTaintsPolicy: Honor` and a verify check; the rerun scaled 1→2→3 with 2 + 1
placement (`verification-runs/fix-2026-10-22/stage7-helm-dev-spread-fix/`).
Reconfirmed in `stages/stage7/helm/apollo11/values.yaml:254` on 2026-10-23.

### G17 — Restore Stage 4 hardening in Stage 5–7 code · A · P1 · done 2026-10-24

**Evidence (2026-10-24):** 18/18 images build, run as UID 10001 (frontend 101) and pass the Trivy gate; the frontend smoke test passes; Stage 5 `/metrics` is Prometheus text; seeded hashes verify with direct `bcrypt`; `test/review/test_images.py` guards the contract; `bash test/ci.sh` passes (`verification-runs/g17-2026-10-24/README.md`). Live Stage 5–7 lifecycles on these images are G1f.

- **Finding [code]:** Stage 5–7 code was not carried forward from the hardened
  Stage 4 snapshot (audit section 4):
  - no `adduser` or `USER` in any Stage 5–7 Dockerfile, so all six app
    containers run as root (compare `stages/stage4/code/booking/Dockerfile:12-26`
    with `stages/stage7/code/booking/Dockerfile`). No chart or overlay sets an
    app `securityContext`.
  - Stage 5 `/metrics` returns JSON (`stages/stage5/code/booking/main.go:209`)
    where Stage 4 returns Prometheus text.
  - the frontend `nginx.conf` drops the non-root pid and temp paths; every
    service loses `.dockerignore`; `frontend/package-lock.json` is gone and the
    Dockerfile runs `npm install`, so builds are not reproducible.
  - identity goes back from direct `bcrypt` to `passlib`.

  `AGENTS.md` and `docs/stage-5.md:53` say Stage 5 code equals Stage 4.
- **Why P1:** a security regression on the required path that contradicts what
  Launchpad–Stage 4 teach, and that blocks G7a.
- **Scope:** `stages/stage{5,6,7}/code/*`. Keep the 2026-10-22 base images and
  dependency upgrades and the Stage 6/7 telemetry and cache code.
- **Deliverables:** non-root numeric `USER` (one UID used everywhere, for example
  10001, to suit Stage 8 `runAsUser`); `.dockerignore`; lockfile plus `npm ci`;
  non-root nginx config; Prometheus text `/metrics` in Stage 5; a stated
  hashing-library decision; a static test in `test/review` that fails when a
  Stage 5–7 Dockerfile has no `USER`.
- **Acceptance:** `grep -L '^USER' stages/stage{5,6,7}/code/*/Dockerfile` prints
  nothing; `docker run --rm --entrypoint id <image>` shows a non-zero UID for all
  18 images; the Trivy gate passes for all 18; `curl` on Stage 5 `/metrics`
  returns `# TYPE` lines; `test/ci.sh` passes. The live proof is G1f.
- **Evidence:** `verification-runs/g17-<date>/` (image UID and Trivy output).
- **Uncertainty:** whether any Stage 4 → 5 difference beyond the upgrades was
  intentional. The record suggests not: Stages 5–7 were built in August, before
  the September hardening rebuilds of Launchpad–Stage 4.

### G18 — Fix Stage 2 lab instructions and frontend expectations · A · P1 · open

- **Finding [code + live-hist]:**
  - The `stages/stage2/README.md` substage 3 break deletes the Secret only in
    `apollo-airlines-apps`. `k8s/substages/03-traefik-ingress-tls/README.md` and
    the S1 run show that only deleting both copies triggers `TRAEFIK DEFAULT CERT`.
  - `scripts/build-images.sh:36-40` always bakes `http(s)://<svc>.apollo.local`.
    Browser API calls therefore cannot work in substage 2 (NodePort, no :80
    listener) or substage 3 (Traefik on :30080/:30443). No README says so.
  - No `/etc/hosts` step and no Docker Desktop MetalLB caveat in the lab
    READMEs (the docs `labs/local-access.md` and `stage-2.md:262-265` have both).
  - The `apply.sh` usage says "Deploy up to substage N", but each run applies
    only substage N.
  - "Comprehensive 30+ check verification suite" (README directory tree) is out
    of date.
  - Added 2026-10-24 from G1c: the substage 2 bundle served at `localhost:30080`
    calls `http://<svc>.apollo.local` with no port, and on a host whose hosts file
    maps those names to the MetalLB IP nothing listens there until substage 4
    (`verification-runs/g1c-2026-10-24/sub2-frontend-bundle.log`) [live].
    `teardown.sh` takes the context only as a positional argument and refuses
    `--context`, unlike `apply.sh` (safe, but inconsistent).
- **Acceptance:** the README break commands match the substage README and S1
  results; each substage section states whether the browser UI works, and
  substages 2–3 point to `curl`; the lab READMEs link to the docs local-access
  page for hosts and Docker Desktop; the `apply.sh` usage text is accurate; the
  check count matches G1c and S1 evidence. If substage-specific frontend bundles
  are added instead, G1c and the substage 3–5 verifiers must pass again.

### G19 — Correct Stage 3 storage teaching; add data-loss and Redis proofs · A · P1 · open

- **Finding [code]:** ROADMAP "Known corrections" asks to reconcile Stage 3's
  node-local volume, binding, replacement and data-loss explanations, and this
  is still open:
  - `stages/stage3/README.md:266-289` says the default class is `local-path (default)`,
    that kind does not use `WaitForFirstConsumer`, and that data is lost when a
    Pod reschedules to another node. In kind the class is `standard`
    (provisioner `rancher.io/local-path`) with `WaitForFirstConsumer`, and the PV's
    `nodeAffinity` pins the Pod to its node. A node outage leaves the Pod
    Pending; removing the node directory loses the data. `docs/stage-3.md:144-150`
    states this correctly.
  - The section heading "Init Container pattern for schema" (`:188`) names the
    rejected design.
  - `k8s/jobs/flight-db-seed.yaml:10-11` says flights have no ON CONFLICT, but
    line 48 uses one.
  - ROADMAP 3.4–3.5: no exercise proves Redis AOF persistence, and none shows
    the PVC-deletion data-loss boundary or a logical backup concept.
- **Acceptance:** the README's `kubectl get sc` sample matches kind's output; the
  replacement and loss semantics match the docs page; the heading and seed
  comment are fixed; new lab steps (a) delete a PVC and show data gone, then
  recover by re-seeding, (b) show a Redis key surviving `redis-0` deletion, and
  (c) restore a `pg_dump` into a scratch database; `verify.sh` gains a Redis
  persistence check; a live run records all three outputs and a 0-failed verify.

### G20 — Stage 4 ROADMAP migration (parent) · A · P1 · open

ROADMAP Stage 4 substages 1–6 and the migration-matrix row "Stage 7 scheduling
lab → Stage 4 substages 4–5". This is approved migration work, not a
regression. If workload manifests change, carry the changes into the Stage 5–7
charts and include them in G1f.

### G20a — Stage 4 probe and termination proofs · A · P1 · open

- **Finding [code]:** the README's experiments are SIGTERM (a log line) and PDB
  eviction only (`stages/stage4/README.md:108-160`). Nothing makes a liveness or
  readiness probe fail, and nothing shows an in-flight request finishing during
  termination (ROADMAP 4.1–4.2). The README hardcodes `172.18.0.50`.
- **Acceptance:** a readiness break (for example scaling `flight-db` to 0) shows
  flight's EndpointSlice endpoint `ready=false` and recovery to `true`; a
  liveness break shows the restart count rising; a load run during
  `kubectl rollout restart deployment/booking` records zero failed requests; the
  README discovers the Gateway IP; `verify.sh` asserts these behaviors.

### G20b — Stage 4 resources, QoS, throttling, OOM, FailedScheduling · A · P1 · open

- **Finding:** ROADMAP 4.3–4.4 (throttling and OOM evidence, scheduling from
  requests) is taught in the docs as concept and troubleshooting
  (`docs/stage-4.md:189-192, 256-257`). The lab has no exercise.
- **Acceptance:** a lab script in a disposable namespace shows `nr_throttled`
  increasing under CPU load at the limit, an `OOMKilled` (exit code 137) memory
  hog, and an oversized request producing `FailedScheduling … Insufficient`;
  each is cleaned up and recovery shown; evidence logged.

### G20c — Stage 4 placement and drain lab with outcome checks · A · P1 · open

- **Finding [code]:** `stages/stage4/scripts/verify.sh:491-517` "Reversible
  Placement Lab" applies a taint and removes it, checking only the taint's
  value, never where any Pod lands. No `kubectl drain` exercise.
- **Acceptance:** with a node tainted, new Pods without the toleration avoid it
  (assert `spec.nodeName`); a tolerating, affinity-preferring workload lands as
  designed; the spread keeps replicas across both workers; `kubectl drain` is
  blocked by `booking-pdb` while it allows 0 disruptions and proceeds once a
  replacement is Ready; `uncordon` and taint removal restore the node. Record
  which scheduling content stays in Stage 7 (feeds G26).

### G21 — Make identity's graceful shutdown real · A · P2 · open

- **Finding [code]:** Stage 4–7 identity Dockerfiles run
  `CMD ["uvicorn", "main:app", ...]`, so the `if __name__ == "__main__":
  uvicorn.run(..., timeout_graceful_shutdown=30)` block in `main.py` never runs,
  and uvicorn's own signal handlers replace the module-level `_log_sigterm`.
  `AGENTS.md` and `docs/stage-4.md:164` say identity drains with a 30 s timeout
  and logs the SIGTERM line [unverified at runtime].
- **Acceptance:** identity starts with an explicit graceful timeout (CLI flag, or
  `python main.py`); deleting an identity Pod logs the SIGTERM line and uvicorn's
  shutdown sequence; a slow in-flight request completes (live); the Stage 4
  verifier and G1f pass.

### G22 — Stage 5 Helm release, rollback, test and comparison labs · A · P1 · open

- **Finding [code]:** ROADMAP 5.1, 5.2 and 5.5 call for Helm releases, rollback,
  chart tests, a Kustomize comparison and promotion. The Stage 5 README has no
  break or recover section, the chart has no `helm.sh/hook: test` templates, and
  `scripts/verify.sh` never runs `helm upgrade`, `helm rollback` or `helm test`.
  The docs teach these concepts, and the lab cannot demonstrate them.
- **Acceptance:** README labs: a bad `helm upgrade` (for example an invalid image)
  → diagnose → `helm rollback` → behavior proven; `helm test` passes with a test
  Pod; one change made in both Helm and Kustomize with the rendered diffs
  compared; dev → staging promotion shown; `verify.sh` asserts the rollback
  revision and the `helm test` result; live evidence recorded.
- **Depends on:** G17.

### G23 — Smooth Launchpad → Ignition → Stage 1 transitions · A · P2 · open

- **Finding [code]:** `stages/ignition/README.md` "Clean up" deletes the cluster
  without saying Stage 1 needs it (the docs `ignition.md:375` say "Keep the
  cluster"). Stage 1 exposes NodePorts 30080–30084 before Stage 2 substage 2
  teaches NodePort (ROADMAP Stage 2.2). Launchpad's seeded schedule is relative
  to volume creation (`code/flight/init.sql:47-61`), so a kept volume runs out
  of future flights after day 30.
- **Added 2026-10-24 from G1b:** `kubectl rollout undo` (kubectl v1.37.1) warns
  that the rollback does not update the `last-applied-configuration` annotation;
  the Stage 1 README's rollback step does not explain it.
- **Acceptance:** Ignition says to keep the cluster for Stage 1, with deletion
  optional; the Stage 1 rollback step explains the `last-applied-configuration`
  warning and that the next `kubectl apply` of the manifest restores agreement; Stage 1 names NodePort as plumbing taught in Stage 2 (or a recorded
  decision to restructure); Launchpad says when to `docker compose down --volumes`
  for a fresh schedule.

### G24 — Correct the docs status page · D · P1 · done 2026-10-24

**Evidence (2026-10-24):** in apollo11-docs on top of `b0838a3`, `docs/status.md` now has an Ignition row, ROADMAP-aligned Stage 9/10/11 tool lists (EKS Pod Identity rather than IRSA), and a CI row saying hosted runs fail and no images are published. `npm run typecheck`, `npm run build` and `git diff --check` pass. A related home-page toolkit issue is G30.

- **Finding [code]:** `docs/status.md`:
  - The "Hosted CI and GHCR" row says the hosted run and publication "remain
    unobserved"; hosted runs exist and fail.
  - The tools table contradicts `ROADMAP.md`: no Ignition row; Stage 9 lists
    IRSA (the plan and prototype use EKS Pod Identity) and omits Terraform,
    cert-manager and Velero; Stage 10 lists Keycloak (not in ROADMAP) and Velero
    (required in Stage 9) and omits the ROADMAP missions; Stage 11 lists Linkerd
    and Chaos Mesh (Stage 10) and Karpenter, OpenCost and Goldilocks (not in
    ROADMAP) while omitting CRD/operator, k3s, Backstage, Kubecost and Cluster
    API; Stage 8 omits Reloader.
- **Acceptance:** start from docs `origin/main` (`b0838a3` or later); each row is
  cross-checked against ROADMAP; the CI row describes the real hosted state with
  a link to this tracker; `npm run typecheck`, `npm run build` and
  `git diff --check` pass.

### G25 — Docs follow-ups to lab changes (parent) · D · P2 · open

Docs change only after the lab change is trustworthy. Each child re-pins the
pages it touches to the Apollo11 commit carrying the lab evidence and re-runs the
docs checks.

### G25a — Docs for Stage 2/3 changes · D · P2 · open

- **Acceptance:** `docs/stage-2.md` states the browser UI boundary per substage
  (G18); `docs/stage-3.md` links the new data-loss, Redis and backup steps (G19);
  links are pinned; docs checks pass.
- **Depends on:** G18, G19.

### G25b — Docs for Stage 4 changes · D · P2 · open

- **Acceptance:** `docs/stage-4.md:164` matches the G21 behavior; the G20 labs
  are walked through with expected outputs taken from G20 evidence; docs checks
  pass.
- **Depends on:** G20a, G20b, G20c, G21.

### G25c — Docs for Stage 5–7 changes and re-pin · D · P2 · open

- **Acceptance:** `docs/stage-5.md:53` describes Stage 5 code correctly (G17);
  least-privilege carry-forward wording matches the images; the G22 Helm labs are
  walked through; the Stage 6 ordered path cites G27; the Stage 7 order matches
  G26; the CI/GHCR wording matches G15; all pins move to one Apollo11 commit with
  every source path checked; docs checks pass.
- **Depends on:** G17, G22, G26, G27, G15.

### G26 — Reorder Stage 7 README; drop duplicate "new" claims · A · P2 · open

- **Finding [code]:** `stages/stage7/README.md:25-35` lists PriorityClass and
  scheduling as Stage 7 "new concepts", but both exist from Stage 4
  (`stages/stage4/k8s/config`). ROADMAP orders Stage 7 as k6 baseline → cache →
  HPA → VPA.
- **Acceptance:** the README follows the ROADMAP order and marks inherited
  mechanisms as inherited, with scheduling content that is left over matching
  the G20c decision.
- **Depends on:** G20c.

### G27 — Live-verify Stage 6's ordered signal path · A · P1 · open

- **Finding:** `stages/stage6/SIGNALS.md:3-5` says the ordered path "requires a
  clean runtime lifecycle before it replaces that verified snapshot". The only
  evidence, `verification-runs/s2-2026-10-19/stage6-helm-dev-signals-lab.sh.log`,
  is a 248-line render with no `created` or `configured` lines. ROADMAP Stage 6
  makes this order the learning path.
- **Acceptance:** from `apply.sh --without-observability`, run
  `signals-lab.sh apply 1..6 helm` in order, with each SIGNALS.md break and
  recover exercised and logged; the final state passes the Stage 6 observability
  checks (`trace-test.sh`, `observability-lab.sh`); teardown is clean; repeat
  once with `kustomize` or record why not.
- **Depends on:** G17 (so the run uses the final images).

### G28 — Decide and prove single-node kind support · A · P2 · open

- **Finding:** every stage script accepts `kind-apollo11-dev` (single node), and
  the Ignition README offers it, but no Stage 2–7 run used it. Stage 4's
  placement checks and Stage 7's scaling lab assume two workers.
- **Acceptance:** a recorded decision. Either single-node runs of Stages 1–7 pass
  (evidence), or scripts from the first stage that needs two workers refuse
  `kind-apollo11-dev` with a clear message and the READMEs and docs say so.

### G29 — Enable or remove the CodeQL workflow · A · P3 · open

- **Finding:** `.github/workflows/codeql-analysis.yml` has never run
  (`total_count: 0`) [hosted]. It is probably disabled in repository settings.
- **Acceptance:** it runs green on `main`, or it is removed with approval.
- **Gates:** repository settings (user).

### G30 — Docs toolkit map lists tools the course never covers · D · P2 · open

- **Finding (2026-10-24) [code]:** `docs/index.md:44` introduces the toolkit as
  "the cloud-native tools the course meets along the way", and the home page
  calls it "the tools you meet along the way" (`src/pages/index.tsx`). The map
  (`src/components/ToolMap/data.ts`) includes tools no ROADMAP stage or mission
  uses, such as Harbor, Rook, Crossplane, Kubespray, Slim, Argo Events,
  Kubescape, TruffleHog, Keycloak, Karpenter, OpenCost and Goldilocks.
- **Acceptance:** every tool on the map belongs to a ROADMAP stage or mission, or
  the map is split and the extra tools are labelled "further reading, not
  taught"; the intro text matches; docs checks pass.

## Reconciliation of the 2026-10-19 items (audit 2026-10-23)

| Old ID | Disposition |
|---|---|
| G1 | Kept as parent, still in-progress. Gaps in its evidence split into G1b (Launchpad/Ignition/Stage 1 not run since code changed), G1c (Stage 2 sub 1/2 no log), G1d (Argo CD), G1e (staging/VPA), G1f (re-run after G17/G21). Historical evidence preserved. |
| G1a | Done; unchanged. CI gating follow-up is new G2b. |
| G2 | **Reopened** on specific contrary evidence: hosted CI fails on the closing commit and every later one. Children G2a, G2b; hosted proof stays G15. |
| G3 | Kept; P1 → P2 (no learner-path impact); split G3a–G3c. |
| G4 | Kept; P1 → P2 (READMEs already warn). The "Stage 8 is README only" part is now accurate. Scope confirmed. |
| G5 | Kept, narrowed: the 69 MB question is answered (ignored `node_modules`); the drift it suspected is real and is now G17. G5 keeps the check and policy. |
| G6 | Kept in-progress; P1 → P2; split G6a (early-stage images), G6b (credentials), G6c (`:latest` decision). |
| G7 | Kept; split G7a–G7e; Reloader from `97232fb` folded into G7c; depends on G17. |
| G8 | Kept as parent; P2 → P1 for the Stage 9 work (required path), still blocked. The guard and the new broken-path finding are G8b; Stage 9 is G8c–G8e. |
| G8a | Kept; P2 → P3 with a recommended resolution. |
| G9 | Kept in-progress; new child G9a. |
| G10 | Kept as parent; split G10a (learner-facing, P1) and G10b (history, P2, approval-gated). |
| G11 | Kept; stale-entry list expanded and dependencies added. |
| G12 | Kept; scope corrected (only `.hermes/plans/*` and `.vscode/settings.json` are tracked). |
| G13 | Kept; CI tool skew and the unused k3d/minikube added. |
| G14 | Done; reconfirmed. No new general alignment task; specific defects are G24 and G25. |
| G15 | Kept; P2 → P0; "never observed" corrected to "observed failing". |
| G16 | Done; fix reconfirmed in the chart. |
| New | G17–G29 (see the summary table); G30 added 2026-10-24. |

## Phase coverage (2026-10-23)

| Phase | Implementation | Strongest evidence | Open IDs |
|---|---|---|---|
| Launchpad | Implemented | [live-hist] 2026-09-05, before code change | G1b, G6a, G8a, G23, G11 |
| Ignition | Implemented | [live-hist] 14/14 2026-09-05, before verifier change | G1b, G23, G28 |
| Stage 1 | Implemented | [live-hist] 167/167 2026-09-05, before code change | G1b, G23, G6a |
| Stage 2 | Implemented | [live-hist] sub 3/4/5 2026-10-19 | G1c, G18, G10a, G25a, G6a |
| Stage 3 | Implemented | [live-hist] 69/69 2026-10-19 | G19, G10a, G25a, G6a |
| Stage 4 | Implemented; ROADMAP migration pending | [live-hist] 149/149 2026-10-19 | G20a–c, G21, G25b, G6a |
| Stage 5 | Implemented; CI never green | [live-hist] 174/163 2026-10-22; Argo 74/74 2026-10-19 | G2a, G15, G17, G22, G1d, G1e, G10a, G25c |
| Stage 6 | Implemented; ordered path unproven | [live-hist] 212/201 2026-10-22 | G27, G17, G1d, G1e, G6b, G10a, G25c |
| Stage 7 | Implemented | [live-hist] 227/216 + capacity 2026-10-22 | G17, G26, G1d, G1e, G10a, G25c |
| Stage 8 | Planned clean rebuild | none | G7a–G7e |
| Stage 9 | Planned; legacy scaffolding | none | G8c–G8e, G4 |
| EKS prototype | Research input; broken path, unguarded | none (Terraform not validated) | G8b |
| Stage 10 | 2 missions verified; rest planned | [live-hist] CNPG, Falco 2026-10-22 | G9, G9a, G4 |
| Stage 11 | Planned; legacy scaffolding | none | G9, G4 |
| Cross-cutting | CI, tests, tooling, status docs | [hosted] CI red | G2a, G2b, G3a–c, G5, G10b, G11, G12, G13, G28, G29 |

Per-phase evidence and the documentation coverage map are in
[`verification-runs/audit-2026-10-23/README.md`](verification-runs/audit-2026-10-23/README.md).
