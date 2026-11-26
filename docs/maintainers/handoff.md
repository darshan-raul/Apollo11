---
title: "Apollo11 — Current Handoff"
description: "Canonical resume point for the learner-roadmap migration and evidence-driven stage rebuild."
---

# Apollo11 current handoff

Updated: 2026-09-05

This file is the concise operational handoff for the next session. Use
`ROADMAP.md` for the approved curriculum architecture, `AGENTS.md` for project
contracts and stage details, and each stage README for learner instructions.
Older completion notes remain available in Git history; they are not repeated
here because several described a curriculum structure that has since changed.

## Current position

- Branch: `main`.
- The roadmap remap and retirement of the legacy Stage 8 tree were committed
  and pushed as `244b037` (`docs: remap learning roadmap and retire stage 8`).
- The Launchpad migration pass described below is complete, verified, and
  committed as `1ddf638` (`launchpad: harden baseline and add learner verification`).
- The Ignition migration pass was committed and pushed as `53c0646`
  (`ignition: add evidence-driven recovery lab`).
- The Stage 1 migration pass described below is complete, verified, and
  included with this handoff.
- No temporary Launchpad containers, volumes, or networks remain.
- The next curriculum migration checkpoint is **Stage 2**. Do not jump
  directly to rebuilding Stage 8.
- Stages 1–7 remain the last existing runnable Kubernetes path while the
  curriculum is migrated one phase at a time.
- Stage 8 has intentionally been deleted. Its replacement must be rebuilt from
  the latest verified Stage 7 Helm baseline and receives no trust from the old
  implementation.
- Stage 9, Stage 10, Stage 11, and `stages/eks` remain planned, optional, or
  prototype material as labeled in `ROADMAP.md` and `AGENTS.md`.

## Approved roadmap decisions

The roadmap was stress-tested in a 45-question grill and approved before any
stage restructuring began. The durable decisions are:

1. The required learner path is Launchpad → Ignition → Stages 1–9.
2. Stages 10 and 11 are optional mission/specialization catalogs with explicit
   prerequisites, not a mandatory linear continuation.
3. Every required substage follows **Build → Inspect → Break → Recover →
   Explain**. Automation is the reproducible answer key, not the learner's only
   interaction.
4. Each phase keeps one independently runnable snapshot. Ordered manifests,
   patches, or scripts represent substages instead of duplicating full trees.
5. Raw Kubernetes resources remain the primary learning surface through Stage
   4. Helm becomes canonical after Stage 5; Kustomize remains a required
   comparison lab rather than a permanently parallel platform definition.
6. Troubleshooting starts in Ignition and grows through status, events,
   `describe`, logs, endpoints, metrics, traces, and policy decisions.
7. Stage 2 preserves the access ladder: ClusterIP/DNS → NodePort → Traefik
   Ingress/TLS → MetalLB → Envoy Gateway API. Envoy becomes the later-stage
   baseline. The Traefik dashboard is optional/reference material.
8. Headless Services are introduced with StatefulSets in Stage 3, not earlier.
9. NetworkPolicy is taught only when enforcement can be demonstrated. The
   current kindnet reference manifests must not be advertised as enforced;
   Calico enforcement belongs in the rebuilt Stage 8.
10. Scheduling concepts previously introduced in Stage 7 move to Stage 4,
    alongside requests, QoS, disruption, and placement.
11. Stage 7 begins with repeatable k6 measurements, then cache-aside behavior,
    HPA, VPA recommendations, and tradeoff analysis.
12. Stage 8 is a clean security rebuild: workload/RBAC hardening, Calico
    NetworkPolicy, Vault plus External Secrets Operator, and Kyverno/Trivy/
    Cosign supply-chain enforcement.
13. Stage 9 is an AWS/EKS-first real-account lifecycle and capstone, including
    cost gates, identity, storage, DNS/TLS, scaling, node failure, upgrade,
    Velero restore, and ownership-scoped teardown. GKE is a required
    portability analysis and an optional second deployment.
14. No stage is marked complete from inert manifests, static renders, or old
    pass counts. Trust requires a fresh lifecycle and observable behavior.

The authoritative details, migration matrix, and correction backlog are in
`ROADMAP.md`.

## Launchpad migration — complete

### Runtime and configuration

- Added `stages/launchpad/.env.example` with `POSTGRES_USER`,
  `POSTGRES_PASSWORD`, and `JWT_SECRET`.
- Updated `.gitignore` to ignore `.env` files while retaining `.env.example`.
- Compose now refuses to render without the required credential variables.
- The default Compose profile contains exactly the ten Apollo Airlines
  workloads. Dozzle moved behind the optional `tools` profile because Docker
  socket access is privileged even with a read-only bind mount.
- All six application containers have health checks and dependency-aware
  startup ordering.

### Container hardening

- All backend Dockerfiles and the frontend runtime declare non-root users.
- Each application service receives a read-only root filesystem, writable
  `/tmp` tmpfs, `no-new-privileges`, and `cap_drop: [ALL]` in Compose.
- Added narrow `.dockerignore` files for backend build contexts.
- The frontend uses `npm ci`, an explicit non-root-compatible NGINX
  configuration, and `/healthz`, `/readyz`, and `/metrics` endpoints.
- Do not mistake these defaults for completion of the security curriculum;
  Stage 8 later makes them explicit, observable, and attackable in Kubernetes.

### Application correctness and observability

- Corrected the invalid `:import os` token in Identity.
- Identity now uses `bcrypt` directly, removing the noisy/incompatible Passlib
  wrapper while retaining existing bcrypt hashes.
- All six applications expose Prometheus text instead of JSON at `/metrics`.
  These are deliberately minimal baseline metrics; real instrumentation and
  collection arrive in Stage 6.
- Search readiness now checks Flight readiness.
- Booking readiness now checks PostgreSQL, Identity, Flight, and Notification.
- Notification's Redis startup wait is bounded to ten seconds and degrades
  cleanly rather than retrying forever.
- Booking forwards the caller's JWT to Identity and generates a short-lived
  `SERVICE` JWT for Flight seat mutations.
- Flight seat mutation accepts the internal `SERVICE` role or an administrator.
  Flight and Booking restrict JWT parsing to HS256.

### Frontend dependency state

- Repaired the stale lockfile that omitted `react-hot-toast` transitive data.
- Updated React Router, Vite, and the Vite React plugin to their audited current
  compatible releases used by the successful container build.
- `npm audit` reports zero vulnerabilities.
- The tracked `dist/` snapshot was restored after verification; source builds
  do not leave generated Vite hashes in the worktree.

### Learner experience

`stages/launchpad/README.md` now provides the complete learner loop:

- create the local `.env` file and start the ten-workload stack;
- inspect health, readiness, metrics, DNS, logs, users, and filesystem controls;
- log in and create a confirmed booking across the flagship dependency path;
- stop Flight PostgreSQL and observe readiness propagation;
- recover the database and prove behavioral recovery;
- replace an Identity database container and prove volume persistence;
- optionally launch Dozzle with an explicit Docker-socket warning; and
- answer the final concept questions before Ignition.

The root README and `AGENTS.md` describe the same verified boundary.

### Automated verifier

Added executable `stages/launchpad/scripts/verify.sh`. It checks:

- ten default workloads and the optional Dozzle profile boundary;
- health, non-root execution, read-only filesystems, no privilege escalation,
  dropped capabilities, and writable `/tmp` for all six applications;
- `/healthz`, `/readyz`, and all three required metric names;
- seeded-passenger login;
- confirmed booking creation and cancellation; and
- request-ID evidence in service logs.

Final isolated run:

```text
Launchpad verification: 73 passed, 0 failed
```

Additional manual evidence:

- With `flight-db` stopped, Flight health/readiness, Search readiness, and
  Booking readiness returned `200 / 503 / 503 / 503` respectively.
- After restarting the database, all three readiness endpoints recovered to
  `200`.
- Identity's seeded user count remained `2` before and after replacing its
  database container, proving the named volume boundary.
- The four Go services passed `go test ./...`.
- Identity passed `python3 -m py_compile main.py`.
- The frontend production build passed and `npm audit` reported zero findings.
- Compose rendering, default-service enumeration, shell syntax, and
  `git diff --check` passed.
- The final isolated project `apollo11-launchpad-final` was removed with its
  volumes and network; the residue query returned nothing.

## Ignition migration — complete

- Replaced the inert sleeping Pod with a pinned BusyBox HTTP workload that
  returns `Apollo11 Ignition ready`.
- Preserved the imperative-to-declarative sequence and made the committed
  manifest the recovery source of truth.
- Added the reusable troubleshooting ladder: status, events, `describe`, logs,
  then endpoint behavior.
- Added one container-process failure that the kubelet recovers inside the
  same Pod UID and one bare-Pod deletion that stays absent until human recovery.
- Added `stages/ignition/scripts/verify.sh`, guarded to Ignition-owned kind
  contexts, which leaves a healthy Pod for learner inspection.
- Passed 14/14 checks on both the pre-existing `apollo11` cluster and an
  isolated fresh three-node `apollo11-ignition-verify` cluster.
- Deleted the isolated cluster and its context, removed the test Pod from the
  pre-existing cluster, and confirmed only the pre-existing `apollo11` cluster
  remains.

## Stage 1 migration — complete

- Ported Launchpad's verified auth propagation, dependency-aware readiness,
  Prometheus text endpoints, non-root images, and frontend build contract into
  the Stage 1 snapshot without replacing its UI source.
- Added 13 dedicated ServiceAccounts. Token automount is disabled, and live
  impersonation checks prove every identity is denied Pod reads.
- Added ordered `apply.sh`, context-guarded `verify.sh`, and ownership-scoped
  `teardown.sh` alongside the hardened image builder.
- Made initialization retries bounded, enabled `psql ON_ERROR_STOP`, retained
  failed Job Pods for diagnosis, and corrected Flight seed uniqueness and SQL.
- Proved two users, 186 flights across 31 days, and the booking schema.
- Exercised a reversible flagship booking with request-ID evidence across
  Booking, Flight, and Notification.
- Deleted a booking Pod and proved ReplicaSet replacement plus endpoint
  recovery.
- Created a successful Search rollout, introduced an invalid image, observed
  the pull failure while old replicas served traffic, and rolled back to the
  working image.
- Final verification passed `167/167` checks.
- Deleted the `apollo-airlines` namespace, found no workload residue, and
  retained the pre-existing `apollo11` kind cluster for Stage 2.

## Important carry-forward constraints

- Each stage owns a self-contained `code/` snapshot. Do not mechanically copy
  the Launchpad tree over Stage 1 or later snapshots. Audit the destination's
  existing correctness fixes, then port only the appropriate baseline behavior.
- Keep example secrets out of real `.env` files. Launchpad database passwords
  should use URL-safe characters because Compose embeds them in connection URLs.
- PostgreSQL initialization credentials apply only to an empty data directory.
  If credentials change after first startup, intentionally recreate the local
  volumes as documented.
- Do not expand the skeleton metrics into a home-grown monitoring system during
  early stages. Stage 6 owns real counters, histograms, scraping, dashboards,
  logs, traces, alerts, and SLO evidence.
- Do not apply reference NetworkPolicies on kindnet or claim enforcement.
- Preserve the Envoy Gateway plus MetalLB access baseline from Stage 2 set 5
  once later stages are reached.
- Do not use the deleted Stage 8 implementation or the legacy Stage 9/10/11
  scaffolding as a trusted source.
- Do not create commits or push unless the user explicitly requests that
  specific action.

## Exact next-session sequence

### 1. Confirm the handoff boundary

```bash
git status --short
git log -2 --oneline
```

The latest commit should contain the Stage 1 closure and this handoff. Preserve
any later unrelated worktree changes during the Stage 2 audit.

### 2. Audit Stage 2 against the approved roadmap

Read, in order:

1. `ROADMAP.md` — Stage 2 target and migration matrix entries.
2. `AGENTS.md` — learner-first lab contract and current project facts.
3. `stages/stage2/README.md`, `NOTES.md`, and every ordered set's referenced
   manifests and scripts.

Produce a concrete gap list before editing. Preserve the last runnable set
while moving concepts to their approved teaching boundary.

### 3. Implement and verify Stage 2

The main gaps to close are:

- begin with ClusterIP Services, cross-namespace DNS, and endpoint inspection;
- keep NodePort as the first direct external access mechanism;
- make Traefik transitional and add controlled local TLS;
- preserve MetalLB before migrating to the canonical Envoy Gateway API;
- introduce consumer-level CRD/controller inspection with Gateway API;
- remove headless Services from Stage 2 and introduce them with StatefulSets;
- remove required/reference NetworkPolicy teaching until Calico enforcement in
  Stage 8; and
- move the Traefik dashboard out of the required progression.

Validate shell/YAML statically first, then use a fresh kind lifecycle for
each routing transition. Preserve a clean teardown after every retained
substage and update completion claims only from behavioral evidence.

### 4. Continue phase-by-phase

Proceed through the migration matrix in `ROADMAP.md`. Rebuild one boundary at a
time, preserve the last runnable path, and never promote an external/cloud
stage without exercising the real external lifecycle and cleanup.
