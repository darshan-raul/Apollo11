---
title: "Apollo11 Gap Tracker"
description: "Open gaps from the 2026-10-19 full-project review, with acceptance criteria and a multi-session plan."
---

# Apollo11 Gap Tracker

Source: full static review on 2026-10-19 at commit `1ac5c66`. This file is the
single place to update gap status. It supersedes the open-item lists in
`AUDIT_GAPS_AND_EXPANSIONS.md` (historical) and the pending gates in
`verification-runs/GAP_CLOSURE.md`.

Status values: `open`, `in-progress`, `done` (with date and evidence), `dropped`
(with reason). Update status and Evidence in the same session that changes it.
Do not mark `done` on static checks alone when the criteria require a live run.

## Already closed (do not redo)

Stage 5–7 kube-context guards; EBS sweep ownership filter; missing
`helm_release` reference in `stages/eks/terraform`; `preStop` and topology
spread in Stage 5–7 charts; `stages/stage7/k6/search.js`; legacy `stage2/set*`
directories; `30088` port references; HTTPS listener on the Envoy Gateway.

## Gaps

| ID | Gap | Priority | Status | Acceptance criteria | Evidence |
|---|---|---|---|---|---|
| G1 | No live proof for the October fixes (HTTPS URLs, cert ownership, token automount, booking SLO, cache benchmark); `AGENTS.md` counts are historical | P0 | in-progress | Fresh apply → inspect → break → recover → teardown for Stage 2 sub 5, 3, 4, then 5/6/7 Helm/dev and Kustomize/dev; actual totals recorded in `verification-runs/`; `AGENTS.md` and READMEs updated to those totals; zero namespace/CRD residue | S1 2026-10-19: Stage 2 sub 5/3/4, Stage 3, Stage 4 apply+verify+teardown passed; see `verification-runs/s1-2026-10-19/`. S2 same day: Stage 5/6/7 Helm and Kustomize dev passed (174/163, 212/201, 227/216), purges clean, see `verification-runs/s2-2026-10-19/`. Closure pass: sub1/sub2 breaks run; Argo CD Stage 5 74/74, Stage 6/7 80/88 and 79/88 under host load (not a pass, rerun on quiet host); Helm/staging not re-run. Fix pass 2026-10-22 (`verification-runs/fix-2026-10-22/`): Stage 5/6/7 Helm and Kustomize dev re-run on upgraded images, 174/163, 212/201, 227/216, purges clean; Stage 6/7 trace-test (Tempo + Loki correlation) and observability-lab pass |
| G1a | SLO rules never run through `promtool`; no real k6 summaries | P0 | done 2026-10-19 | `promtool test rules` passes (install promtool first); two saved k6 summaries (cache off/on) with environment record | promtool 3.15.0 installed via `mise use -g promtool` (2026-10-19); `promtool test rules` passes on live rules; k6 cache off/on summaries saved in `verification-runs/s2-2026-10-19/` |
| G2 | CI builds only `stages/stage5/code`; Stage 6/7 code never built; GHCR images would ship Stage 5 code | P0 | done 2026-10-22 | CI builds and tests the code the published tag claims to ship (Stage 7 or a matrix); runs `test/review` Python tests, `go test` for search, helm lint/render for Stages 5–7; `shellcheck` over all `stages/**/*.sh`; Trivy image scan step | CI matrix across stages 5, 6, 7 and all 6 services; Trivy gate pinned by commit (trivy-action v0.36.0, Trivy v0.70.0); exact scanned image published on push/tag. First config failed the gate (search: 2 CRITICAL, 54 HIGH); after the G6 upgrade all 18 images pass locally (`verification-runs/fix-2026-10-22/trivy/`) and `test/ci.sh` passes (`verification-runs/fix-2026-10-22/ci-local.log`). Hosted run tracked in G15 |
| G3 | Almost no automated tests beyond `test/review` and `search/cache_test.go` | P1 | open | Unit tests for auth/JWT, booking flow, and seat logic in at least identity, flight, booking; run in CI; `test/stageN_test.sh` wrappers either do real work or are removed | |
| G4 | Legacy library-management code tracked in Stage 9/10/11; 12 tracked `dist/` bundles; Stage 8 is README only | P1 | open | Legacy `auth/catalog/circulation/fines` trees, stage9–11 `k8s`/`terraform` scaffolding, and tracked `dist/` removed (confirm with user before deleting); READMEs keep planned status; ROADMAP unchanged | |
| G5 | `stages/*/code` copied 10 times, 69 MB in `launchpad/code`; per-stage copies of `generate-certs.sh`, `context.sh`, `verify-tls.sh` | P2 | open | Script that diffs snapshots and fails on unexpected drift, run in CI; investigate why `launchpad/code` is 69 MB and remove untracked/build artifacts from the tree; decide and document copy vs shared script policy | |
| G6 | Supply-chain hygiene: Go 1.22 EOL, unpinned `alpine`/`nginx:alpine`, `:latest` tags in dev/staging, plaintext teaching Secrets not labelled everywhere | P1 | in-progress | Supported Go version across services and Dockerfiles with tests passing; base images pinned by version; teaching Secrets labelled in each README; decision recorded on `:latest` | 2026-10-22, Stages 5–7 only: Go 1.27.3 builders with module deps upgraded (`go 1.26.0`), pinned `alpine:3.24.2`, `nginx:1.30.6-alpine3.24`, `node:22.23.4-alpine3.24`, `python:3.12.15-slim-trixie`, runtime `apk upgrade`; identity on FastAPI 0.159 / Starlette 1.9; all 18 images pass Trivy and live lifecycles (`verification-runs/fix-2026-10-22/`). Open: earlier stage snapshots still on Go 1.22; Secret labelling; `:latest` decision |
| G7 | Stage 8 unbuilt (RBAC/PSA, Calico NetworkPolicy, Vault+ESO, Kyverno/Trivy/Cosign) | P1 | open | Built from the Stage 7 Helm baseline under the learner-first contract, one substage at a time, each with a live lifecycle | |
| G8 | Stage EKS prototype and Stage 9 unbuilt; EKS scripts lack account/context guard; prototype based on Stage 2/3 | P2 | open | Add account-ID and context allowlist to `stages/eks/scripts/*` now; rebuild on the Stage 7 platform only after explicit authorization for a real AWS lifecycle with zero owned residue | |
| G8a | `launchpad/scripts/verify.sh` has no context/daemon safety check | P2 | open | Guard or documented reason it is not needed | |
| G9 | Stage 10/11 optional missions unbuilt | P3 | in-progress | Each mission as an independent lab with baseline, experiment, restore, cleanup | CloudNativePG and Falco missions built and verified live 2026-10-22 (`verification-runs/fix-2026-10-22/cnpg-*`, `falco-*`); remaining Stage 10/11 missions open |
| G10 | Status docs overlap and contradict: `AGENTS.md`, `AUDIT_GAPS_AND_EXPANSIONS.md`, `DOCS_IMPROVEMENT_REPORT.md`, `handoff.md`, `.handoff.md`, `stages/stage7/.handoff.md`, `verification-runs/*` | P1 | open | One status source (this tracker plus `AGENTS.md`); handoff files merged into it or removed; stale patch/"uncommitted" language in `GAP_CLOSURE.md` updated; stale audit items marked superseded | |
| G11 | `AGENTS.md` is 1000+ lines and has stale entries (Stage 2 layout/NetworkPolicy wording, Stage 3 count 53 vs 68) | P2 | open | Split per-stage detail into stage READMEs; keep `AGENTS.md` under ~300 lines; counts match the latest verified runs | |
| G12 | Tracked noise: `.hermes/plans`, `.devbox`, `.vscode`, empty `.agents` and `.codex` | P3 | open | Remove or gitignore after confirming with user | |
| G13 | `mise.toml` uses `latest` for every tool; no stated RAM/CPU minimum for Stage 6+7 on kind | P2 | open | Tools pinned to the versions the verifiers passed on; minimum resources documented | Note from S2: labs flake when host load average far exceeds core count; document a quiet-host requirement |
| G14 | Sibling `apollo11-docs` patch application and docs revision status unknown | P1 | done 2026-10-22 | Check whether `apollo11-docs-gap-fixes.patch` is applied; apply, build and typecheck in that repo; record revision | Audited docs base `aada9b0` plus existing storage edits; aligned active pages directly to code `f6211e6` (last five commits). Historical patch targets superseded page structure; reverse-apply check cannot establish application history, so it was not blindly applied. `npm run typecheck`, `npm run build`, `git diff --check` pass; 94 pinned source paths resolve locally. Existing edits preserved. Review mapping: sibling `apollo11-docs/maintenance/repo-alignment-2026-10-22.md`; docs alignment commit `4c36bfe` on docs main (integrated with `254a191`); typecheck and build repeated after integration. |
| G15 | Stage 5 hosted GitHub Actions run and first GHCR publication never observed | P2 | open | Hosted run green; images published; evidence linked | |
| G16 | `stages/stage7/scripts/scaling-lab.sh` is flaky: soft node-affinity preference vs `ScheduleAnyway` spread sometimes puts every Search replica on one worker (failed 3 of 4 Helm runs, passed Kustomize) | P1 | done 2026-10-19 | Lab passes 5 of 5 on Helm and on Kustomize; scheduling policy decision recorded (`DoNotSchedule` spread or preferred anti-affinity) | Spread changed to `DoNotSchedule`; 10/10 passes (`verification-runs/s2-2026-10-19/g16/`). Follow-up 2026-10-22: the k6 capacity run showed a third replica Pending, because the default `nodeTaintsPolicy: Ignore` counted the tainted control plane as an empty domain. Added `nodeTaintsPolicy: Honor` and a verify check; rerun scaled 1→2→3 with 2 + 1 placement (`verification-runs/fix-2026-10-22/stage7-helm-dev-spread-fix/`) |

## Session plan

| Session | Scope | Gaps |
|---|---|---|
| S1 | Live lifecycle Stage 2–4, record totals; install promtool | G1 (part), G1a |
| S2 | Live lifecycle Stage 5–7 (Helm and Kustomize), SLO fixture, k6 summaries, residue audit | G1, G1a |
| S3 | CI rework: build current code, tests, shellcheck, render checks, Trivy | G2, G3 (CI hookup), G15 |
| S4 | Service unit tests; Go and base image upgrades | G3, G6 |
| S5 | Cleanup: legacy trees, `dist/`, noise files, snapshot drift check | G4, G5, G12 |
| S6 | Docs consolidation: handoff merge, `AGENTS.md` split, docs-repo patch | G10, G11, G14, G13 |
| S7+ | Stage 8 substages, one per session | G7 |
| Later (needs explicit authorization) | EKS guard now (small); real AWS lifecycle; Stage 9; Stage 10/11 | G8, G8a, G9 |

## Rules for each session

1. Read this file and `AGENTS.md` first.
2. Work only the gaps scoped to that session; update their rows before ending.
3. Record live evidence as files under `verification-runs/`, and link them in the Evidence column.
4. Do not commit, push, delete tracked content (G4, G12) or touch AWS without explicit user approval.
