# Apollo11 Audit — Verified Gaps, Live-Check Backlog, Decisions, and Verification Playbook

**Revision:** 2 (vetted) — 2026-10-04
**Audited commit:** Apollo11 `7b693c9` (`main`, clean worktree except this file); apollo11-docs `a5b29c1`.
**Rules for this document:** it is analysis only. No repo file other than this one was changed, nothing was committed, and **no cluster, container, or cloud resource was created or mutated** to produce it. Read-only `kubectl get`, `git`, `grep`, `ls` only.

## Current disposition

This is the historical pre-fix audit of `7b693c9`, not a current open-issue list.
The October fix commit and subsequent working-tree corrections supersede some
findings and decisions. Use `verification-runs/GAP_CLOSURE.md` for disposition,
current checks, and remaining runtime gates; do not reuse the pinned commands
below as verification of a newer revision.

## How to read this file

Every item has an ID and a confidence class. Do not act on an item without checking its class.

| Class | Meaning |
|---|---|
| **VERIFIED** | Confirmed by a read-only command in this session. The evidence command is listed; re-run it before acting. |
| **LIVE-CHECK** | Plausible or claimed by docs/AGENTS.md, but only a real apply → verify → break → recover → teardown run can confirm it. **Not trusted until a session runs it** (section 3). |
| **DECIDED** | The owner has made the call. Implementation has **not** started. |
| **PROPOSAL** | Expansion idea; no commitment. |

### Revision 1 retractions (do not re-introduce)

Revision 1 of this audit contained claims that did not survive vetting:

| Retracted claim | Why |
|---|---|
| Docs' `storageClassName: standard` breaks on kind | **Wrong.** `kubectl --context kind-apollo11 get sc` shows the default class is literally named `standard` (provisioner `rancher.io/local-path`, `WaitForFirstConsumer`). The docs are correct. The repo's phrase "local-path StorageClass" names the provisioner, which is confusing but not a bug. |
| "kind v1.35.0 does not exist" (Stage 5 README) | **Wrong.** It is the Kubernetes node version; the live cluster reports server `v1.35.0`. Only the wording ("kind v1.35.0") is loose. |
| devbox lacks `cosign`/`kyverno` | AGENTS.md says tools are added only when their lab is verified. Not a defect. (The leftover `opa` entry is a minor cleanup, see V-17.) |
| Stage 6 "no SLOs" evidence in `values-staging.yaml` | That comment is about PDBs. SLO absence is re-established differently in V-05. |
| `set*` dirs = "88 files / 50,000 lines" | I used a commit stat. Real figure: 125 tracked files, ~4.4 MB (V-08). |
| Stage 1 NodePort "steals" Stage 2's lesson | Stage 1's README intentionally teaches ClusterIP + NodePort; ROADMAP only says "Services". Downgraded to a sequencing note (N-02). |
| Stage 5–7 lacking the Stage 4 contract is a "mistake" | It is the planned migration backlog (ROADMAP: one phase at a time). Kept as a dependency (V-04), not a defect. |
| Ignition leftover Pod, docs NetworkPolicy/scheduling claims, Promtail in docs, Stage 9 booking SQL | Unverified, archived, or legacy scaffolding slated for deletion. Dropped. |
| Several line numbers (AGENTS.md 588/883/887, SPEC 369) | Wrong; corrected below. |

---

## 1. VERIFIED findings

### Safety (act first)

**V-01 — `stages/eks/scripts/ebs-sweep.sh` deletes every unattached EBS volume in the region.** Lines 22–24 filter only `status=available`; no tag, cluster, or ownership filter, then `delete-volume` in a loop. Also the `RED` color is malformed (`'\033[0-31m'`) here and in `down.sh:27`.
*Aggravating context:* the local kubeconfig currently contains a **real AWS EKS context** (`arn:aws:eks:us-east-1:084828572570:cluster/darshan-test`). ROADMAP already lists region-wide EBS cleanup as a required correction.
*Evidence:* `sed -n 15,45p stages/eks/scripts/ebs-sweep.sh`; `kubectl config get-contexts`.

**V-02 — Stage 5/6/7 and Launchpad scripts have no kube-context guard; Stages 1–4 and Ignition do.**
`grep -ln "current-context\|kind-apollo11\|ALLOWED_CONTEXTS" stages/*/scripts/*.sh` lists only `stage4/scripts/{apply,teardown,verify}.sh` and `ignition/scripts/verify.sh` (Stages 1–3 enforce `kind-apollo11|kind-apollo11-dev` inline in `apply.sh`). Stage 5–7 `apply.sh` will Helm-install into **whatever `current-context` is**. With an EKS context present, a mis-set context would install the platform (including Envoy/MetalLB bundles and a cluster-scoped purge path in `teardown.sh --purge`) into a real cluster. Treat as a safety defect, not polish. Until fixed, sessions must follow section 5.1.

**V-03 — `stages/eks/terraform/gateway/envoy-gateway.tf:27` depends on `helm_release.aws_load_balancer_controller`, which is defined nowhere** (`grep -rn helm_release stages/eks/terraform` returns only that reference). `down.sh:75` also targets it. Terraform cannot validate. (Tree is already labeled untrusted; this confirms ROADMAP's known-correction list.)

### Correctness

**V-04 — Stages 5, 6, 7 do not carry the rebuilt Stage 4 contract.** `grep -rln preStop stages/stage{5,6,7}/helm/apollo11/templates` → 0 files each. `topologySpreadConstraints` appears only in `stage7/.../apps/search.yaml`. `stage5/helm/apollo11/values.yaml:328-330` still says priority is "reserved for Stage 7+" and sets `priorityClassName: ""`. This is the dependency chain for the planned Stage 5→8 migration (Stage 8 rebuilds from the Stage 7 Helm baseline), so it must be resolved there, not patched ad hoc.

**V-05 — Stage 6 has alert rules but no SLI/SLO or error-budget content.** Alerts exist (`ApolloServiceDown`, `ApolloServiceFlapping`, `ApolloErrorRateHigh`, `ApolloBookingLatencyP95High` in `stages/stage6/helm/apollo11/templates/observability/prometheus/rules.yaml`). No recording rules, burn-rate alerts, or error-budget exercise exist; ROADMAP Stage 6 item 3 promises them. Stage 6 also installs the whole stack in one apply, not as the ordered signal-by-signal substages ROADMAP specifies.

**V-06 — k6 baseline does not exist.** No k6 script anywhere in the tree. ROADMAP Stage 7 item 1 requires one; `apollo11-docs/docs/learn/scaling/measurement-baseline.md` tells the learner to run `k6 run stages/stage7/k6/search.js`. Stage 7 currently uses a BusyBox curl-loop Deployment in `scripts/scaling-lab.sh`. Docs→lab path audit (section 5.5) found this and `stages/stage8` as the **only** missing cited paths out of 95.

**V-07 — Launchpad seeds 6 flights, not ~186.** `stages/launchpad/code/flight/init.sql:14` has `flight_number VARCHAR(20) UNIQUE NOT NULL`; the 30-day `INSERT … generate_series` (lines 50–69) uses `ON CONFLICT (flight_number) DO NOTHING`, so every generated row conflicts with the seed row and is skipped. Additionally all generated flights use the same 08:00/14:30 times regardless of route. Stages 1–7 use `UNIQUE (flight_number, departure_time)`. `launchpad/scripts/verify.sh` has no flight-count assertion, so "73/73" cannot detect this. **Still LIVE-CHECK to confirm the count** (see L-01), but the SQL semantics are unambiguous. SPEC.md:363 carries the same constraint.

**V-08 — Stage 2 still ships the five legacy `set1…set5` directories.** 125 tracked files, ~4.4 MB (`du -sh stages/stage2/set*` → 228K/264K/280K/348K/3.2M; `git ls-files stages/stage2 | grep -E '/set[1-5]-' | wc -l` counts them with their parents). No script references them; AGENTS.md lines 141–145 still list them as current. See D-1.

**V-09 — Stage 2 README and docs cite port `30088`; the manifest uses `30080`.** `git grep 30088` → only `stages/stage2/README.md` (and docs `stage-2.md`). `…/03-traefik-ingress-tls/01b-traefik-service.yaml` uses `nodePort: 30080/30443`, and kind maps 30080–30084 and 30443 only.

**V-10 — Envoy Gateway (Stage 2 substage 5 onward) is HTTP-only.** `…/05-envoy-gateway/01-gateway.yaml` has a single `protocol: HTTP`, port 80 listener; `grep -rn "protocol: HTTPS" stages` → nothing. Substage 3 teaches local TLS then the canonical stack drops it, and every later stage inherits plain HTTP. See D-2.

**V-11 — `stages/stage8/` does not exist** (docs reference it and flag it as absent). Stages 9–11 have status READMEs; Stage 8 has none. See D-3.

**V-12 — Stages 9, 10, 11 contain legacy library-management scaffolding** (`auth, catalog, circulation, fines`) under `code/` and `k8s/`. READMEs already say "do not apply". They are gitignored for `node_modules` (not tracked), but the legacy source/manifests are tracked.

### Documentation drift (in Apollo11)

**V-13 — AGENTS.md contradicts itself on verify counts.** Stage 4: `148/148` at lines 51 and 462, but `130 checks` at 155, 577, and `130/130` at 907. Stage 3: `53/53` at 906 vs `68/68` in `stages/stage3/README.md`. Stage 2: the completion table (905) still reports the legacy per-set counts (25/26/27/26/29) while the section above it reports 46/48/49/46/57. Stage 4's `AGENTS.md` code-evolution table also still says "All 5 Go services" where it means four plus Identity.
**V-14 — SPEC.md is stale** (lines 26/62/67/68/508/674): says Stage 3 uses "init containers" (it uses the entrypoint hook), Stage 8 uses "OPA", Stage 9 does "Terraform for EKS + GKE", and load testing/k6 is "Stage 9". All conflict with ROADMAP.
**V-15 — `stages/stage2/README.md:58`** says verify has "30+ checks" (actual 46–57). Minor.
**V-16 — Stage 5 README calls the cluster "kind v1.35.0"** — wording only (see retractions).
**V-17 — Minor cleanups:** `devbox.json` still lists `opa` (ROADMAP selected Kyverno) and its init hook text says only "kubectl, minikube, docker, task"; `test/util/` is empty; `test/stage{5,6,7}_test.sh` wrappers are missing although SPEC.md:26 promises per-stage test scripts; `.hermes/plans/2026-06-02_apollo11-rebuild-plan.md` is a stale tracked plan; `ignition/kind-config-single.yaml:33` comment says "unused in Set 1".

### Operational hazards worth recording

**V-18 — All stages tag images `apollo11/<svc>:latest`.** Stage 1 builds the frontend with NodePort URLs (`localhost:3008x`), later stages bake `*.apollo.local` URLs. Switching stages without rebuilding silently runs the wrong frontend image against the new routing. Local Docker already holds stale `apollo11/*:latest` plus `apollo11-launchpad-{final,verify}-*` images from earlier sessions. **Always rebuild when switching stages; never use `--skip-build` as the first run.**
**V-19 — Stage 1 injects `VITE_*` via `envFrom` ConfigMap into the frontend container** while the actual URLs are baked at image build. The ConfigMap values do nothing at runtime. Teaching-risk (a learner may believe editing the ConfigMap re-points the SPA), not a functional bug.

---

## 2. Findings that are NOT bugs (record so they are not re-raised)

- **N-01** Docs `storageClassName: standard` is correct on kind (see retractions).
- **N-02** Stage 1 includes NodePort Services intentionally (its README says so). Optional sequencing refinement only: some learners meet NodePort in Stage 1 and again as "first external access" in Stage 2 substage 2.
- **N-03** Stage 4 is rebuilt; Stages 5–7 are not yet. Per ROADMAP this is the schedule, not drift.
- **N-04** Stage 6 telemetry (Alloy replaces Promtail) is current; the Promtail mention is only inside the archived `stages/stage7/.handoff.md`.

---

## 3. LIVE-CHECK backlog — "do the stages we claim to work actually work?"

This is the section that matters most. **No stage's "complete" status has been re-proven by this audit.** All counts below are claims from README/AGENTS.md. A stage is only trusted after a session executes the playbook in section 5 and records evidence.

| ID | Stage | Claim to test | Claimed result | Date of last claimed proof | Notes |
|---|---|---|---|---|---|
| L-01 | Launchpad | `verify.sh` passes; flight rows | 73/73 | 2026-09-04 | Also **count seeded flights** (expect 186 if fixed; expect 6 as-is — V-07). Includes manual break/recover. |
| L-02 | Ignition | fresh 3-node lifecycle | 14/14 | 2026-09-05 | Use the existing `apollo11` cluster or an isolated verify cluster. |
| L-03 | Stage 1 | apply → verify → teardown, zero residue | 167/167 | 2026-09-05 | Includes failed-rollout + rollback. |
| L-04 | Stage 2 | each substage 1–5 verified separately | 46/48/49/46/57 | 2026-09-11 | Run **one substage at a time**, tearing down between. Also confirm no HTTPS (V-10). |
| L-05 | Stage 3 | StatefulSets + PVC survival | 68/68 (README) vs 53/53 (AGENTS) | 2026-09-11 | Resolve which count is real (V-13). |
| L-06 | Stage 4 | reliability + Eviction proof | 148/148 (AGENTS L51/462) vs 130 (L155/577/907) | 2026-09-11 | Resolve which count is real. |
| L-07 | Stage 5 | Helm/dev, Kustomize/dev, Argo CD | 153 / 142 / 74 | 2026-08-22 | Predates the Stage 4 rebuild; Argo needs a Git fixture; hosted CI/GHCR are external and unproven. |
| L-08 | Stage 6 | Helm/dev, Kustomize/dev, trace test | 190 / 180 | 2026-08-25 | Argo layout only statically validated. |
| L-09 | Stage 7 | Helm/dev, Kustomize/dev, `scaling-lab.sh` 1→3→1 | 211 / 200 | 2026-08-26 | VPA is **disabled in dev**; live VPA proof needs `--env staging`. Pods need ≥2 labeled workers. |
| L-10 | Docs | Each lab page's commands behave as written against `7b693c9` | n/a | 2026-09-18 | Run per section 5.4. Docs status page claims "Launchpad through Stage 7 is the supported local path". |

Expected honest outcomes to watch for: Stage 5–7 may fail or pass for reasons unrelated to Stage 4 (their last proof is 3–6 weeks and a rebuild old); AGENTS.md counts may be wrong in either direction; Stage 2 substage scripts were rewritten on 2026-09-11 with only the claimed pass counts as evidence.

---

## 4. DECISIONS (all approved by owner on 2026-10-04) — implementation not started

| ID | Decision | Scope notes for the implementer |
|---|---|---|
| **D-1** | **Delete Stage 2 `set1…set5` directories.** | Allowed by ROADMAP trust rule 3 (the substage replacement is claimed to have passed its lifecycle) — **but only after L-04 is re-proven**, otherwise you would delete the last known-good path. In the same change: update AGENTS.md tree (lines 141–145), the Stage 2 completion row (905), and the narrative at 398–404. Do not remove `NOTES.md` (Envoy version sweep). Check nothing else imports `set*` paths (initial grep: nothing). |
| **D-2** | **Add an HTTPS listener to the Envoy Gateway baseline.** | Reuse the `apollo-tls-secret` model from substage 3 (`generate-certs.sh`). Needs a `protocol: HTTPS`/port 443 listener with `certificateRefs`, a TLS secret in the Gateway's namespace (note: Gateway lives in `apollo-airlines-apps`), MetalLB already exposes 80/443-capable IPs. Decide whether HTTP→HTTPS redirect is in scope. Update Stage 2 substage 5 README + verify (+ a negative check), then propagate to Stage 3/4 gateway dirs and the Stage 5–7 Helm `gateway/` templates (their frontend VITE URLs are `http://*.apollo.local` and must change in lockstep, plus the browser-trust caveat for a self-signed cert). Larger blast radius than it looks; do it as its own change and re-verify every downstream stage. |
| **D-3** | **Add a Stage 8 placeholder README.** | Mirror `stage9/README.md` style (YAML front matter, "Status: not implemented", pointer to ROADMAP, the four ordered substages, "no trust inheritance"). Docs `stage-8.md` already links `stages/stage8`. Recommended companion: update the docs path-audit expectation. |

---

## 5. VERIFICATION PLAYBOOK (instructions for other sessions)

### 5.0 Goal and ground rules

Goal: for each stage the project claims is working, **independently reproduce the claim on a clean cluster, record evidence, and cross-check the matching apollo11-docs pages.** Output is a results file, not code changes.

Ground rules:

1. **Do not edit repo files, do not `git commit`/push** (AGENTS.md: commit only when explicitly asked). Write results only to `/home/darshan/projects/Apollo11/verification-runs/` (create it; it is outside any stage and can be deleted) — or to the session's artifact directory.
2. **One stage at a time. Tear down fully before the next.** Host has 6 CPUs / 15 GB RAM; running two stacks starves both and produces false failures.
3. **Never run anything under `stages/eks/`, `stages/stage9/`, `stages/stage10/`, `stages/stage11/`.** There is a live AWS EKS context on this machine (V-01/V-02).
4. **Do not touch** the `lockin-postgres-1` container or any non-Apollo Docker resource.
5. **Use the existing kind cluster `apollo11`** (3 nodes, server v1.35.0, default StorageClass `standard`). It is pre-existing; **do not delete the cluster**, only the stage workloads. Baseline observed before this audit: namespaces `default kube-node-lease kube-public kube-system local-path-storage` only (no Apollo namespaces). After each stage teardown, return to exactly that baseline.
6. **Never trust a green verify alone.** The curriculum's own rule is that pass counts show consistency, not understanding. For each stage also perform the README's manual Inspect/Break/Recover step by hand at least once and note whether the README's expected output is what you actually saw.

### 5.1 Safety setup (mandatory before every session)

Stages 5–7 and Launchpad have no context guard (V-02). Isolate yourself from the EKS context:

```bash
mkdir -p /home/darshan/projects/Apollo11/verification-runs
export KUBECONFIG=/tmp/apollo11-only-kubeconfig
kind export kubeconfig --name apollo11 --kubeconfig "$KUBECONFIG"
kubectl config get-contexts          # must list ONLY kind-apollo11
kubectl config current-context       # must print kind-apollo11
```

Pre-flight (record all output in the run log):

```bash
cd /home/darshan/projects/Apollo11
git rev-parse HEAD                   # expect 7b693c9bae0a789dc9db8e0628c478fd0dd53e88 (the docs pin this)
git status --short                   # expect only AUDIT_GAPS_AND_EXPANSIONS.md (+ verification-runs/)
kind get clusters                    # expect: apollo11
kubectl get nodes                    # 3 Ready, v1.35.0
kubectl get ns                       # baseline above; any apollo-* ns means a previous run was not cleaned
docker ps --format '{{.Names}}'      # note unrelated containers; do not touch
```

If any Apollo namespace exists, **stop** and clean it with that stage's `teardown.sh` (or ask) before measuring anything.

### 5.2 Evidence record (use for every stage)

Create `verification-runs/<UTC-timestamp>_<stage>.md` with:

```
Stage:            <name>        Commit: <git rev-parse HEAD>        Context: <kubectl config current-context>
Started/Ended:    <timestamps>
Images built:     fresh build (yes/no)         Host: 6 CPU / 15 GB
Commands run:     <exact lines, in order>
Automated verify: <final summary line, pass/fail counts, claimed count>   -> MATCH / DIFFERS (explain)
Manual Inspect:   <what README said to expect> vs <what you observed>
Manual Break:     <experiment> -> <observed failure symptoms>
Manual Recover:   <action> -> <behavioral proof (HTTP response, row count), not just 'Pod exists'>
Teardown:         <command> -> residue check output (must equal baseline)
Docs cross-check: <page(s)> -> <discrepancies found>   (section 5.4)
Verdict:          WORKS / WORKS-WITH-DOC-DRIFT / BROKEN / INCONCLUSIVE   + one-line reason
```

A stage is **WORKS** only if the automated verify count matches the claim (or the difference is explained and benign), manual break/recover matches the README, teardown returns to baseline, and the docs page does not mislead. Anything else is a finding, to be entered in a new "Results" section of this file by the owner/requested session — do not silently "fix" the stage.

### 5.3 Per-stage procedure

Always `cd /home/darshan/projects/Apollo11` first. Read the script header/`--help` before running; flags below were read from the scripts. **Always rebuild images (no `--skip-build`) on the first run of each stage (V-18).** Run the commands from the repo root unless the stage README says otherwise (Stage 6/7 READMEs use `cd stages/stageN` + `bash scripts/...` — both forms work; be consistent).

| Stage | Setup | Automated | Manual labs (from the README) | Teardown + residue |
|---|---|---|---|---|
| **Launchpad** | `cd stages/launchpad && cp -n .env.example .env`, set URL-safe values (Docker only, no cluster; compose project is separate from kind) | `bash scripts/verify.sh` (read header: it may create its own isolated project) | §3 prove, §5 stop `flight-db` → `/readyz` 503 on flight/search/booking → restart → 200; §6 persistence (user count unchanged). **Extra:** `docker compose exec flight-db sh -c 'psql -U "$POSTGRES_USER" -d flight -c "select count(*) from flights"'` — record the number (expect 6 per V-07, claimed 186). | `docker compose down --volumes`; `docker ps -a`, `docker volume ls`, `docker network ls` show no `launchpad*`. Leave `.env` untracked (it is gitignored). |
| **Ignition** | cluster `apollo11` already exists | `bash stages/ignition/scripts/verify.sh` (takes optional context as `$1`; context-guarded) | README imperative → declarative; kill the HTTP process (same Pod UID, restart count +1); delete the bare Pod (stays absent until re-apply, new UID). | Delete the Ignition Pod per README cleanup; `kubectl get pods -A` back to baseline. |
| **Stage 1** | none | `bash stages/stage1/scripts/apply.sh` then `bash stages/stage1/scripts/verify.sh` | README Inspect 1–6: ownership chain, EndpointSlices, ConfigMap/Secret describe, `kubectl auth can-i … --as=system:serviceaccount:apollo-airlines:booking` = `no`, Job logs; Break: bad-image rollout → `ImagePullBackOff` while old replicas serve; Recover: `rollout undo`. | `bash stages/stage1/scripts/teardown.sh`; `kubectl get ns` has no `apollo-airlines`. |
| **Stage 2** | none; run **each substage separately** | for N in 1..5: `bash stages/stage2/scripts/apply.sh --substage N`, `bash stages/stage2/scripts/verify.sh` (auto-detects the active layer), then `bash stages/stage2/scripts/teardown.sh` before N+1 | Per-substage README under `stages/stage2/k8s/substages/0N-*/README.md`: 1 break selector → endpoints `<none>`; 2 break `targetPort`; 3 delete `apollo-tls-secret` → Traefik default cert, recover with `generate-certs.sh`; 4 delete IP pool → `<pending>`; 5 patch HTTPRoute to `9999` → `ResolvedRefs=False`. Also: confirm **no 443/HTTPS** on the Envoy IP (V-10) and note whether the `30088` port in the README works (it should not, V-09). | `bash stages/stage2/scripts/teardown.sh` (it claims 0 residue). Also confirm `envoy-gateway-system`, `metallb-system`, `traefik` namespaces/CRDs are gone. |
| **Stage 3** | none | `bash stages/stage3/scripts/apply.sh`, `bash stages/stage3/scripts/verify.sh` | README: `delete pod identity-db-0`, row count unchanged; inspect PVC/PV (`kubectl get pvc,pv -A`, node affinity of the local-path PV); optionally note where `Pending` appears if the worker is cordoned. **Record the true total check count** (README says 68, AGENTS says 53). | `bash stages/stage3/scripts/teardown.sh`; **also check PVCs/PVs are gone** (`kubectl get pv`) — StatefulSet PVCs are not deleted with the set by default. |
| **Stage 4** | none | `bash stages/stage4/scripts/apply.sh --cluster apollo11`, `bash stages/stage4/scripts/verify.sh` | README Experiments 1 (SIGTERM drain log) and 2 (second Eviction rejected with `TooManyRequests`); additionally check `qosClass` Guaranteed, `kubectl get pdb -A`. **Record the true check count** (148 vs 130). | `bash stages/stage4/scripts/teardown.sh`; confirm no leftover PriorityClasses `apollo-airlines-app-*` (cluster-scoped), PVs, or taints on nodes (`kubectl describe node | grep -i taint`). |
| **Stage 5** | `cd stages/stage5` | `bash scripts/apply.sh --mode helm --env dev` → `bash scripts/verify.sh --mode helm --env dev` (check `--help`; verify may infer env) → `bash scripts/teardown.sh --mode helm --env dev --purge`. **Repeat** with `--mode kustomize --env dev`. Argo CD (`argocd/scripts/{bootstrap,verify,teardown}.sh`, claim 74): needs a reachable Git revision — only attempt if the owner approves a fixture; otherwise mark **INCONCLUSIVE (external)**. | `helm list -A`, `helm get values`, change a value + `helm upgrade` + `helm rollback` (the README claims releases/rollback but ships no Break/Recover loop — record that gap). Hosted GitHub Actions/GHCR cannot be verified locally: mark **external/unproven**. | `--purge` removes namespaces and cluster-scoped resources; verify baseline **and** no leftover CRDs (`kubectl get crd | grep -E 'gateway|metallb|monitoring|argoproj'`). |
| **Stage 6** | `cd stages/stage6` | `bash scripts/apply.sh --mode helm --env dev`, `bash scripts/verify.sh --mode helm`, `bash scripts/trace-test.sh`; teardown with `--purge`; repeat for `--mode kustomize` | Port-forward Prometheus (9090)/Grafana (3000) per README; confirm 5 targets UP, 5 dashboards, a booking trace (booking+identity+flight+notification) in Tempo, Alloy logs in Loki, `grafana.apollo.local` through Envoy. **Break (not in README — propose one):** stop one backend's scrape (scale to 0) → target DOWN/`ApolloServiceDown` fires → restore. | `--purge`; confirm `apollo-observability` ns, Prometheus Operator CRDs gone. Heavy stack: allow extra time; watch memory. |
| **Stage 7** | `cd stages/stage7` | `bash scripts/apply.sh --mode helm --env dev`, `bash scripts/verify.sh --mode helm`; `bash scripts/scaling-lab.sh` (search 1→3→1; needs ≥2 workers labeled `node-role=worker`; it adds/removes a taint+label itself) ; teardown `--purge`; repeat Kustomize. Live VPA only with `--env staging` (VPA is off in dev). | `curl -i -H 'Host: search.apollo.local' http://<EnvoyIP>/api/search?...` twice → `X-Cache: MISS` then `HIT`; `kubectl get hpa -n apollo-airlines-apps -w`; `kubectl describe vpa search-vpa` (staging). **Note:** no k6 baseline exists (V-06); do not try to run the docs' k6 command. | After the lab, `kubectl get nodes --show-labels | grep search-pool` and taints must be empty; `scaling-lab.sh cleanup` if interrupted. `--purge`, then baseline check. |

Helpful commands during every stage:

```bash
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe pod <pod> -n <ns>        # status -> events -> describe -> logs -> endpoint behaviour
kubectl logs <pod> -n <ns> --tail=100
ENVOY_IP=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl -i -H 'Host: frontend.apollo.local' "http://$ENVOY_IP/"
```

Failure triage (before declaring BROKEN): (1) wrong context/namespace/stage leftovers (`kubectl get ns`); (2) stale images (rebuild; V-18); (3) host resource starvation (`kubectl top nodes`, `free -g`); (4) leftover cluster-scoped objects from a prior stage (CRDs, PriorityClasses, PVs, webhooks — especially Envoy Gateway webhooks hanging namespace deletion; teardown scripts order deletion for that reason); (5) a genuine defect — capture `describe` + logs + the failing check name.

### 5.4 Docs cross-check procedure (apollo11-docs as the reference)

The docs are paired with Apollo11 `7b693c9` (see `docs/status.md`, `docs/labs/setup.md` — "Clone the tested lab revision"). Repo HEAD equals that commit, so doc/lab mismatches are real mismatches. Mapping:

| Stage | Lab page | Concept chapters (`docs/learn/…`) | Mission page |
|---|---|---|---|
| Launchpad | `launchpad.md` | `containers/*` | `missions/launchpad.md` |
| Ignition | `ignition.md` | `cluster/*` | `missions/ignition.md` |
| 1 | `stage-1.md` | `workloads/*` | `missions/liftoff.md` |
| 2 | `stage-2.md` | `networking/*` | `missions/guidance.md` |
| 3 | `stage-3.md` | `storage/*` | `missions/mission-data.md` |
| 4 | `stage-4.md` | `reliability/*` | `missions/flight-control.md` |
| 5 | `stage-5.md` | `delivery/*` | `missions/payload-integration.md` |
| 6 | `stage-6.md` | `observability/*` | `missions/mission-operations.md` |
| 7 | `stage-7.md` | `scaling/*` | `missions/orbital-maneuvering.md` |
| 8/9/EKS | `stage-8.md`, `stage-9.md`, `eks.md` | `security/*`, `cloud/*` | conceptual only — **do not execute** |

For each stage, after the automated verify has passed, **read the lab page as a learner would** and run its commands literally in order:

1. **Path/name audit (static, cheap — already run once; re-run after any change):**
   ```bash
   cd /home/darshan/projects/apollo11-docs
   grep -rohE 'stages/[A-Za-z0-9_./*-]+' docs --include=*.md | sed -E 's/[.,;:)]+$//' | sort -u > /tmp/doc_paths.txt
   while read p; do case "$p" in *'*'*) continue;; esac
     [ -e "/home/darshan/projects/Apollo11/$p" ] || echo "MISSING $p"; done < /tmp/doc_paths.txt
   ```
   Result on 2026-10-04: 95 distinct paths; only `stages/stage7/k6/search.js` and `stages/stage8` missing (V-06, V-11).
2. **Identifier audit:** for every namespace, Service/Deployment name, NodePort/port, hostname, label, and image tag the page mentions, confirm it exists in the running stage (`kubectl get …`) or the stage manifests. Examples already known wrong: port `30088` (V-09).
3. **Command audit:** run each fenced `bash` block (skip those marked planned/conceptual). Record: ran as written / needs edit (what) / output differs from the documented "expected" (paste both).
4. **Manifest excerpt audit:** where the docs label a snippet "exact excerpt", `diff` it against the named source file; flag unlabeled adaptations. (Revision 1's `storageClassName: standard` suspicion turned out to be correct docs — verify, don't assume.)
5. **Claim audit:** where docs assert a mechanism (e.g. "Gateway attaches across namespaces via ReferenceGrant", "preStop runs inside the grace period"), find the manifest/log that proves it in the running lab.
6. **Status-claim audit:** `docs/status.md` and each page's banner say what is supported; flag any page that implies a stage works when your run says otherwise, or says "planned" for something that runs.

Record discrepancies with page + line, observed behavior, and the lab file at fault (docs vs lab — AGENTS.md says the lab is the source of truth, so the doc is normally the one to change).

### 5.5 Suggested session order and work split

1. **Session A (setup + cheap):** 5.1 safety, then Launchpad, Ignition, Stage 1. These are the oldest rebuilt and cheapest. Include L-01 flight count.
2. **Session B:** Stage 2, substage by substage (the heaviest manual narrative; needs HTTPS observation for D-2 and the 30088 check).
3. **Session C:** Stage 3, then Stage 4 (resolve the 68/53 and 148/130 counts).
4. **Session D:** Stage 5 Helm, then Kustomize (Argo/CI marked external unless approved).
5. **Session E:** Stage 6, then Stage 7 (heavy; run alone).
6. **Docs session (can run in parallel with *static* work only):** 5.4 items 1, 2, 4 statically; 3/5/6 need a live stage.

Each session ends by returning the cluster to the baseline in 5.1 and committing nothing.

### 5.6 What to do with the results

Do **not** start fixing during verification. After L-01…L-10 have verdicts, the owner reviews them, then fixes go in the order: (1) V-01/V-02 safety guards, (2) documentation truth (V-09, V-13–V-17), (3) V-07 Launchpad seed + count assertion (re-verify Launchpad), (4) D-1 after L-04 is proven, (5) D-3 placeholder, (6) D-2 as its own change with downstream re-verification, (7) the ROADMAP migration of Stages 5→6→7 (absorbing V-04, V-05, V-06), then Stage 8 and Stage 9. Each rebuilt stage needs its own fresh apply → inspect → break → recover → teardown proof before any "complete" claim.

---

## 6. EXPANSION proposals (labelled PROPOSAL; none committed)

Retained from revision 1, restated against ROADMAP (all optional until the owner schedules them):

- **P-01 Stage 4:** an explicit OOMKill demo (limit breach → exit 137, `Last State: OOMKilled`) and an ephemeral-storage example to tie cgroups to Pod status.
- **P-02 Stage 5:** `helm test` hook; an Argo CD app-of-apps/ApplicationSet root; a real Break/Recover loop (failed `helm upgrade` → `helm rollback`; Argo drift + self-heal).
- **P-03 Stage 6:** the promised SLI/SLO exercise — booking success-ratio recording rule, multi-window burn-rate alerts, an injected-failure error-budget run; ordered signal-by-signal substages with one Break/Recover each.
- **P-04 Stage 7:** the missing k6 suite (`stages/stage7/k6/`), cold vs cache-warm runs, a summary-comparison script, replace the BusyBox load loop, and move/remove the duplicated scheduling lab (ROADMAP: scheduling lives in Stage 4).
- **P-05 Stage 8:** the four-substage security rebuild from the Stage 7 Helm baseline (RBAC/PSA → Calico NetworkPolicy → Vault+ESO → Kyverno/Trivy/Cosign), each with a demonstrable deny/reject.
- **P-06 Stage 9:** rebuild AWS/EKS from the hardened Helm snapshot with explicit cost gates, tag-scoped teardown, cert-manager TLS, node-drain and upgrade drills, a Velero restore, and a required EKS→GKE portability analysis.
- **P-07 Harness:** add `test/stage{5,6,7}_test.sh` wrappers; add flight-count/schema assertions to Launchpad; add a kube-context guard shared by every stage script.
- **P-08 Hygiene:** purge or replace the legacy Stage 9–11 scaffolding with Apollo-specific stubs; reconcile SPEC.md with ROADMAP; clean `devbox.json`.

---
*End of revision 2.*
