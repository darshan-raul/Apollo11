# S2 live lifecycle — 2026-10-19

Commit `1ac5c66` plus uncommitted fixes. Fresh `kind-apollo11` (3 nodes), images rebuilt
by `apply.sh` on the first run of each stage. `first-pass/` holds the earlier sweep
(failed Kustomize runs, fixed below); `first-attempt/` holds the first Stage 5 Helm run.
Top-level `stage*-*.log` are the second sweep.

| Run | Verify | Labs | Residue after `--purge` |
|---|---|---|---|
| Stage 5 Helm/dev | 174/174 | – | none |
| Stage 5 Kustomize/dev | 163/163 | – | none |
| Stage 6 Helm/dev | 212/212 | signals-lab, trace-test pass; slo-lab passes after fix (run on a Stage 7 stack) | none |
| Stage 6 Kustomize/dev | 201/201 | – | none |
| Stage 7 Helm/dev | 227/227 | trace-test pass; scaling-lab FAILED (see below) | none |
| Stage 7 Kustomize/dev | 216/216 | scaling-lab passed 4/4 on an earlier Kustomize stack | none |

Residue audit lists namespaces, PVs, CRDs, and metallb/envoy/prometheus/vpa/argocd/etc.
cluster-scoped objects; only the built-in `system:monitoring` role remains.

## Defects found and fixed
- Stage 5/6/7 `verify.sh` frontend-bundle check grepped `http://` and so could not see the
  `https://` hosts the October fix introduced. Now `https?://`.
- Stage 5/6/7 `teardown.sh --purge` left MetalLB/Envoy Gateway ClusterRoles, bindings and
  webhook configurations. Now removed.
- Stage 6/7 Kustomize `overlays/base/generated.yaml` set `automountServiceAccountToken: false`
  on `observability-stack`, so Alloy could not read its token and crash-looped. The Helm
  template does not set it. Line removed in both.
- `stages/stage6/scripts/slo-lab.sh` hit a draining flight Pod and got 201 instead of 502.
  Now waits for the Pods to be deleted.

## Open
- `stages/stage7/scripts/scaling-lab.sh` is flaky: it failed on Helm 3 of 4 runs
  (`search replicas used only 1 worker`) and passed on Kustomize. The Search node-affinity
  preference (labelled worker) and the `ScheduleAnyway` topology spread are both soft and
  normalised, so placement is close to a tie. Needs a design decision (see GAPS_TRACKER G16).
- An intermittent 502 in the trusted-HTTPS workflow check appeared once each in Stage 5 and
  Stage 7 Kustomize in the first pass and did not recur in the second sweep.

## SLO and cache evidence
- `promtool/`: rules extracted from the live `apollo-services` PrometheusRule;
  `promtool check rules` and `promtool test rules` (`test/stage6_slo_rules_test.yaml`) pass.
  Prometheus after `slo-lab.sh`: `apollo:booking_error_ratio:5m` 0.992,
  `apollo:booking_error_budget_remaining:28d` −193.
- `k6/`: cache off p95 10.0 s, median 1.13 s, 25% failed requests, 2790 dropped iterations
  (single Search replica cannot sustain 50 req/s; exit 99 by threshold); cache on p95 10.7 ms,
  median 2.8 ms, 0 failures, hit rate 99.98%. `environment.txt` has commit, nodes and image.
  The first attempt (`k6/first-attempt/`) is invalid: port-forward was not ready.

## Closure pass (same day)
- **G16 fixed:** Search `topologySpreadConstraints` now `DoNotSchedule` (Helm values, Kustomize
  generated.yaml, verifier, README). Scaling lab passed 10/10 (`g16/`, 5 Helm + 5 Kustomize).
- **Stage 2 sub 1/2 breaks** run live (selector break -> curl exit 7; targetPort break -> exit 56);
  recovered; READMEs' expected health body corrected to `{"status":"ok"}`.
- **Intermittent 502 / identity startup / API timeouts:** reproduced only while host load average
  was 35-77 on 6 cores (Quartz builds, Firefox, btrfs I/O). `identity-flake/` has the 5-cycle run.
  Environmental; no code change. Labs need a quiet machine (see G13).
- **Argo CD (git:// fixture via `git daemon`, local only):**
  - Stage 5: 74/74, purge clean (`argocd/`).
  - Stage 7: 80/88, Stage 6: 79/88 (`argocd/stage7/`, `argocd/stage6/`). Failures are identity
    (startup probe `connection refused`, CrashLoopBackOff) plus dependants (staging flight/booking,
    observability) while host load was ~77. A Stage 7 rerun (`argocd/stage7-rerun/`) showed the same
    identity CrashLoopBackOff under load. **Not a pass; Argo Stage 6/7 need a rerun on a quiet host.**
  - Argo `teardown.sh --purge` (Stages 5-7) previously left MetalLB/Envoy roles, a webhook and two
    PriorityClasses; patched. Stage 5/6/7 purges after the patch left zero namespaces, CRDs or
    cluster-scoped residue.
- Helm/staging not re-run (August evidence only).
