---
title: "Curriculum and documentation audit — 2026-10-23"
description: "Evidence for the 2026-10-23 audit of the Apollo11 lab and apollo11-docs. Findings and tasks live in GAPS_TRACKER.md; this file holds the evidence only."
---

# Curriculum and documentation audit — 2026-10-23

This file is evidence. It holds no task list. Every finding below maps to an ID
in [`GAPS_TRACKER.md`](../../GAPS_TRACKER.md), which is the only backlog.

Evidence labels used here and in the tracker:

- **[code]** read in source; behavior inferred, not run.
- **[static]** a local static check ran in this audit and passed (command given).
- **[hosted]** read from GitHub's public API in this audit.
- **[live-hist]** a live run recorded earlier under `verification-runs/`; not repeated here.
- **[unverified]** no evidence either way.

No cluster, container, image, cloud resource, commit, push or hosted workflow
was created or triggered by this audit.

## 1. Baseline

| Item | Value |
|---|---|
| Review date | 2026-10-23 |
| Apollo11 local HEAD | `5790cd9ad61b3c9cce7876a1a728150f0973f88f` on `main`, clean before this audit |
| Apollo11 `origin/main` (GitHub API) | `97232fb` (2026-10-23, PR #80): docs-only Stage 8 Reloader plan touching `ROADMAP.md`, `AGENTS.md`, `README.md`, `SPEC.md`, `stages/stage8/README.md`, and the G7 row of `GAPS_TRACKER.md`. **Not fetched**: `git fetch` was denied by the session's permission policy, so this audit reviewed `5790cd9`. |
| apollo11-docs local HEAD | `8362c51c876dc8c8a86fd1f5f252ec18bb98ae99` on `main`, clean |
| apollo11-docs `origin/main` (GitHub API) | `b0838a3` (2026-10-23): merge of `45eb1ac` "docs(stage8): explain config-change rollouts and planned Reloader". Not fetched. |
| Docs source pin | Apollo11 `f6211e6` (82 blob and 12 tree links; `docs/status.md`, `docs/labs/setup.md`) |
| Prior evidence reused | `verification-runs/s1-2026-10-19/`, `s2-2026-10-19/`, `fix-2026-10-22/`, `later-stage-2026-10-22/`; docs `maintenance/repo-alignment-2026-10-22.md` |

Local tools available: kubectl v1.37.1, kind v0.33.0, Helm v4.3.1, Kustomize
v5.8.3 (kubectl embeds v5.8.1), jq, shellcheck 0.11.0, Trivy, promtool 3.15.0,
k6 v2.3.0, Go 1.25.10 (`GOTOOLCHAIN=auto`), Python 3, Docker, Node v26.1.0, npm.
Not installed: `terraform`, `gh`, `yq`, `actionlint`, `kubeconform`,
`markdownlint`. The AWS MCP server failed to connect (no credentials), which
did not matter because AWS was out of scope.

## 2. Checks performed in this audit

| Command (cwd) | Outcome |
|---|---|
| `python3 test/generated.py --check` (Apollo11) | pass [static] |
| `python3 -m unittest discover -s test/review` (Apollo11) | 20 tests, OK [static] |
| `find stages -name '*.sh' -print0 \| xargs -0 shellcheck -S warning` (Apollo11) | no findings [static] |
| `bash -c 'diff -rq -x node_modules -x dist -x __pycache__ stages/<a>/code stages/<b>/code'` for each consecutive pair | see section 4 [static] |
| `npm run typecheck` (apollo11-docs) | pass, 2.1 s [static] |
| `npm run build` (apollo11-docs) | `[SUCCESS] Generated static files in "build"`; only Node `localStorage` ExperimentalWarnings; `onBrokenLinks`, `onBrokenMarkdownLinks` and `onBrokenMarkdownImages` are all `throw` [static] |
| `GET /repos/darshan-raul/Apollo11/actions/workflows/main.yml/runs` | 30 most recent CI runs, 2026-06-17 → 2026-10-23: **all `failure`** [hosted] |
| `GET .../actions/runs/39821233584/jobs` (`5790cd9`) and `.../39985772897/jobs` (`97232fb`) | job "Helm + Kustomize validate" fails at step "Validate all maintained charts, overlays, scripts, and tests"; build and publish skipped [hosted] |
| `GET .../actions/workflows/codeql-analysis.yml/runs` | `total_count: 0` [hosted] |
| `GET /repos/darshan-raul/Apollo11/tags` | `[]`: no release tags exist [hosted] |

Not run, and why: `test/ci.sh` as a whole (its `go test -race` would download
the Go 1.26 toolchain, which counts as installing a dependency); any `kind`,
Compose or image build (the audit was not allowed to change clusters or
images); Terraform validation (not installed, and AWS was out of scope); failed
CI job logs (the GitHub API needs authentication, and `gh` is not installed).

## 3. Phase coverage

Each row: what was inspected, the strongest evidence that exists, and the
tracker IDs for the gaps found.

| Phase | Inspected | Strongest evidence | Findings → IDs |
|---|---|---|---|
| Launchpad | README, `docker-compose.yml`, `.env.example`, `scripts/verify.sh`, Dockerfiles, `flight/init.sql` | [live-hist] 2026-09-05 run; code then changed in `1ac5c66` (2026-10-09: booking, flight, identity, search, `init.sql`, compose, verify) | No live run since `1ac5c66` → G1b. Verifier counts 74 checks (3 profile + 6×11 per service + 5 workflow), but AGENTS.md says 73 (`:245`) and 74 (`:916`) → G11. Bases `golang:1.22-alpine`, `alpine:3.19`, `node:20-alpine`, unpinned `nginx:alpine`, `python:3.12-slim` → G6a. Verifier has no Docker context check → G8a. Seed schedule is relative to volume creation (`CURRENT_DATE + n`), so a persisted volume ages past day 30 → G23. |
| Ignition | README, `pod.yaml`, both kind configs, `scripts/verify.sh` | [live-hist] 14/14 on 2026-09-05; `verify.sh` changed in `f6211e6` | No run since the verifier change → G1b. The README's cleanup deletes the cluster without saying Stage 1 needs it (the docs page says "Keep the cluster") → G23. |
| Stage 1 | README, `scripts/{apply,verify,teardown,build-images}.sh`, Services | [live-hist] 167/167 on 2026-09-05; code changed in `1ac5c66` | No live run since → G1b. Stage 1 exposes NodePorts 30080–30084 before Stage 2 teaches NodePort (ROADMAP Stage 2.2) → G23. Context guard and teardown are sound. |
| Stage 2 | README, 5 substage READMEs, `apply.sh`, `build-images.sh`, `teardown.sh`, verifier outline | [live-hist] sub 3/4/5 on 2026-10-19 (`s1-2026-10-19/`). Sub 1/2: no October log | Sub 1/2 not re-run → G1c. The main README's substage 3 break deletes only the apps-namespace Secret, which the substage README and the S1 run show does not trigger the fallback → G18. Frontend bundle is always `http(s)://<svc>.apollo.local` (`build-images.sh:36-40`), so browser API calls cannot work in substage 2 (NodePort, no :80) or 3 (Traefik on :30080/:30443) [code] → G18. The lab README has no `/etc/hosts` step and no Docker Desktop/MetalLB caveat (the docs have both) → G18. `apply.sh --substage N` usage text says "up to" but applies only N → G18. Stale "working tree" banner → G10a. |
| Stage 3 | README, seed Jobs, verifier outline | [live-hist] 69/69 on 2026-10-19 | README says kind's default class is `local-path (default)` and that data is lost when a Pod reschedules to another node (`README.md:266-289`). In kind the class is named `standard`, binds `WaitForFirstConsumer`, and local-path PVs pin the Pod to one node through `nodeAffinity` (the docs page has this right) → G19. `flight-db-seed.yaml:10-11` says flights have no ON CONFLICT, but line 48 uses `ON CONFLICT (flight_number, departure_time)` → G19. ROADMAP 3.4–3.5 (Redis persistence proof, node/storage constraint, backup concept, data-loss boundary) has no lab or verifier step → G19. Stale banner → G10a. AGENTS.md says 68 checks in its file table → G11. |
| Stage 4 | README, `verify.sh` sections 12 and 16, identity Dockerfile and `main.py` | [live-hist] 149/149 on 2026-10-19 | `verify.sh:491-517` "placement lab" only applies a taint and removes it; it never checks a scheduling result → G20c. The SIGTERM experiment shows a log line, not that an in-flight request finished (ROADMAP 4.2) → G20a. No OOM, CPU throttling, FailedScheduling, `kubectl drain` or probe-failure exercise (ROADMAP 4.3–4.6) → G20a, G20b, G20c. The README hardcodes `172.18.0.50` → G20a. Identity runs the `uvicorn` CLI (`Dockerfile:20`), so the `uvicorn.run(..., timeout_graceful_shutdown=30)` block in `main.py` never runs → G21. |
| Stage 5 | README, `values-prod.yaml`, CI workflow, `test/ci.sh`, Argo CD layout, code diff against Stage 4 | [live-hist] Helm 174/174 and Kustomize 163/163 on 2026-10-22; Argo CD 74/74 on 2026-10-19 (before the 10-22 image upgrade) | Hosted CI has failed on every run since June; no tags exist, so `values-prod.yaml` `tag: v1.0.0` cannot be pulled → G2a, G15. README says the workflow was "statically validated" and the hosted run "occurs on the next push/tag" → G10a. Verify target 153/142 vs recorded 174/163 → G10a. No Helm upgrade/rollback/`helm test` exercise and no Kustomize comparison or promotion lab (ROADMAP 5.1, 5.2, 5.5); the chart has no test hooks → G22. Code is **not** a Stage 4 snapshot: 30 files differ (section 4) → G17. |
| Stage 6 | README, OBSERVABILITY.md, SIGNALS.md, `signals-lab.sh`, evidence logs | [live-hist] Helm 212/212, Kustomize 201/201, trace-test, observability-lab on 2026-10-22; Argo CD 79/88 on 2026-10-19 | The ordered signal path (`signals-lab.sh apply 1..6` from `apply.sh --without-observability`) has no live evidence: `s2-2026-10-19/stage6-helm-dev-signals-lab.sh.log` is a 248-line render with no `created`/`configured` lines → G27. Argo CD never passed → G1d. Grafana `admin`/`apollo-admin` is a plaintext teaching credential → G6b. Stale banner and "hosted CI requires a push" text → G10a. |
| Stage 7 | README, PERFORMANCE.md, `.handoff.md`, scaling-lab, evidence | [live-hist] Helm 227/227, Kustomize 216/216, capacity 1→2→3 on 2026-10-22; Helm/staging with live VPA 211/211 on 2026-08-25 only; Argo CD 80/88 on 2026-10-19 | Helm/staging and live VPA not re-run since the image upgrade → G1e. Argo CD → G1d. README presents PriorityClass and scheduling as Stage 7 "new concepts"; both already exist in Stage 4, and ROADMAP moves scheduling to Stage 4 → G26. `stages/stage7/.handoff.md` is archived but still tracked → G10b. |
| Stage 8 | `stages/stage8/README.md` (only file) | none (planned) | Planned clean rebuild → G7a–G7e. README calls Stage 7 "the hardened baseline", but Stage 5–7 images run as root → G17 must precede G7a. Remote `97232fb` adds Reloader to substage 3, recorded in G7c. |
| Stage 9 | README, legacy `code/` (auth, catalog, circulation, fines), `k8s/`, `terraform/` | none (planned; README warns not to apply) | Planned → G8c–G8e. Legacy library-era scaffolding → G4. |
| Stage 10 | README, `missions/cloudnativepg/*`, `missions/falco/*` | [live-hist] CNPG failover 7 s plus logical restore; Falco detection on 2026-10-22 | Both missions run in their own kind cluster with a private kubeconfig and full teardown: sound. Falco pulls its chart from GitHub at apply time and failed three times on network timeouts → G9a. Remaining missions → G9. Legacy trees → G4. |
| Stage 11 | README, legacy `code/`, `k8s/` (crds, operators) | none (planned) | → G9 (catalog) and G4 (legacy). |
| EKS prototype | README, `scripts/*.sh` (paths and guards) | none; Terraform not validated (not installed) | `apply-workloads.sh:105` applies `stages/stage3/k8s/serviceaccounts/`, which does not exist (ServiceAccounts are in `k8s/config/`), so the script aborts at step 3 under `set -e` [code] → G8b. No AWS account allowlist; `up.sh:57` runs `aws eks update-kubeconfig`, which silently switches the current context; `apply-workloads.sh` uses the current context unguarded → G8b. |
| Cross-cutting | `.github/workflows/*`, `test/`, `mise.toml`, tracked noise, status documents | [hosted] CI history | CI red since June → G2a/G15. CodeQL workflow has never run → G29. CI pins Helm v3.16.2, kubectl v1.30.0, Trivy v0.70.0 while the local passing runs used Helm v4.3.1, kubectl v1.37.1, Trivy 0.75.0 → G2a, G13. promtool SLO fixture is not in CI → G2b. Only `search` has Go tests and identity has none → G3. `.hermes/plans/*` (3 files) and `.vscode/settings.json` are tracked; `.devbox` does not exist; `.agents`/`.codex` are empty untracked directories → G12. 12 tracked `dist/` files in launchpad and Stages 9–11 despite `.gitignore` → G4. The 69 MB in `launchpad/code` and 73 MB in each of Stages 9–11 is ignored `node_modules`, not tracked content → closes that G5 question. Single-node `kind-apollo11-dev` is accepted by every script but has no recorded run for Stages 2–7, and Stage 4/7 placement checks assume two workers → G28. |

## 4. Code snapshot drift

`diff -rq` between consecutive `stages/*/code` trees, excluding
`node_modules`, `dist`, `__pycache__`:

| Pair | Files differing | Expected? |
|---|---|---|
| launchpad → stage1 | 7 (frontend only: CSS, pages, Tailwind, Vite config) | Plausible (Stage 1 URL defaults); undocumented |
| stage1 → stage2 | 0 | yes |
| stage2 → stage3 | 0 | yes |
| stage3 → stage4 | 6 (`main.go` ×4, `main.py`, frontend `nginx.conf`) | yes: probes and SIGTERM |
| **stage4 → stage5** | **30** | **No.** AGENTS.md and the docs say Stage 5 code is unchanged from Stage 4. |
| stage5 → stage6 | 14 (OTEL, metrics, deps) | yes |
| stage6 → stage7 | 5 (search cache and tests) | yes |

Stage 4 → 5 regressions observed [code]:

- Every Stage 5–7 Dockerfile drops `adduser` and `USER`, so all six app
  containers run as **root** in Stages 5–7. No Helm template or Kustomize base
  sets a `securityContext` for app workloads in any stage.
- Stage 5 `/metrics` returns JSON (`c.JSON(...)`) instead of Stage 4's
  Prometheus text exposition (`booking/main.go:209`).
- Stage 5–7 frontend `nginx.conf` loses the non-root `pid`/temp-path settings
  and the `/metrics` location. Stages 5–7 also lose `.dockerignore` for every
  service and `frontend/package-lock.json`, and the Dockerfile uses
  `npm install` without a lockfile, so builds are not reproducible.
- Stage 5–7 identity goes back from direct `bcrypt` to `passlib`.

## 5. Documentation coverage map

Docs inventory: 152 files under `docs/`; navigation in `sidebars.ts` (one
category per phase plus Mission Briefing, Beyond the Mission, and Flight Kit &
Reference). Every phase has a mission briefing, concept chapters and a
walkthrough. Planned phases are labeled "not implemented" or "concepts only".

| Phase | Docs pages | Coverage against lab and ROADMAP | Gaps → IDs |
|---|---|---|---|
| Onboarding | `start/*` (4), `labs/setup.md`, `labs/local-access.md`, `troubleshooting.md`, `command-reference.md`, `glossary.md` | Prerequisites, pinned checkout, mise, Docker Desktop and MetalLB limits, hosts file and trust | none new |
| Launchpad | `missions/launchpad`, `learn/containers/*` (5), `launchpad.md` | Full | G25b if Stage 5–7 non-root is restored (least-privilege carry-forward wording) |
| Ignition | `missions/ignition`, `learn/cluster/*` (7), `ignition.md`, `flight-deck/*` (4) | Full; says "Keep the cluster" | none |
| Stage 1 | `missions/liftoff`, `learn/workloads/*` (5), `stage-1.md` | Full | none |
| Stage 2 | `missions/guidance`, `learn/networking/*` (6), `stage-2.md` | Full, with Docker Desktop caveats; explains which URL scheme the frontend bundle uses | G25a: say the browser UI only works from substage 4 on (after G18) |
| Stage 3 | `missions/mission-data`, `learn/storage/*` (6), `stage-3.md` | Accurate on `standard`/`WaitForFirstConsumer`/`nodeAffinity` and recovery boundaries | G25a: link any new lab steps from G19 |
| Stage 4 | `missions/flight-control`, `learn/reliability/*` (6), `stage-4.md` | Concepts cover OOM, throttling, FailedScheduling and drain as explanation and troubleshooting, not as labs | G25b: `stage-4.md:164` says identity runs with `timeout_graceful_shutdown=30` (false, G21); add labs after G20 |
| Stage 5 | `missions/payload-integration`, `learn/delivery/*` (5), `stage-5.md` | Helm rollback and promotion are taught conceptually | G25c: `stage-5.md:53` says code is the Stage 4 services "carried over" (false, G17); CI/GHCR wording after G15 |
| Stage 6 | `missions/mission-operations`, `learn/observability/*` (7), `stage-6.md` | Ordered `signals-lab.sh` path documented | G25c after G27 confirms it live |
| Stage 7 | `missions/orbital-maneuvering`, `learn/scaling/*` (4), `stage-7.md` | k6, cache, HPA, VPA, scaling lab | G25c after G26 |
| Stage 8 | `missions/command-module`, `learn/security/*` (4), `stage-8.md` | Status accurate (not implemented). Reloader page is on remote `b0838a3`, not local | G7e |
| Stage 9 / EKS | `missions/lunar-orbit`, `learn/cloud/*` (4), `stage-9.md`, `eks.md` | Status accurate (planned, prototype untrusted) | G8e (after implementation) |
| Capstone | `learn/capstone/*`, `capstone.md` | Labels Stage 8/9 controls as planned | none |
| Stage 10 | `stage-10.md`, `labs/cloudnativepg.md`, `labs/falco.md` | Two runnable missions, rest planned | none |
| Stage 11 | `stage-11.md` | Status accurate | none |
| Status page | `status.md` | Mostly accurate | G24: "hosted run and publication remain unobserved" is false (runs exist and fail). The tools table contradicts the ROADMAP: no Ignition row; Stage 9 lists IRSA (the plan and prototype use EKS Pod Identity); Stage 10 lists Keycloak (not in ROADMAP) and Velero (required in Stage 9); Stage 11 lists Linkerd and Chaos Mesh (Stage 10) and Karpenter, OpenCost and Goldilocks (not in ROADMAP) while omitting CRD/operator, k3s, Backstage, Kubecost and Cluster API; Stage 8 omits Reloader. |

G14 (docs alignment to `f6211e6`) stands: this audit found no general alignment
regression, only the specific items above. Do not open another general
docs-alignment task.
