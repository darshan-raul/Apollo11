# Gap closure: implementation, documentation, and verification

Date: 2026-10-05. Base source commit: `143cac8bb7e611db25f87582a178b44ae2d2fb1e`.
Docs base: `d041b64`. Both original worktrees were clean before this work.
All source changes are uncommitted; no push or deployment was performed.

## Scope and disposition

| Gap | Implemented correction | Evidence / remaining gate |
|---|---|---|
| Unsafe Stage 5–7 teardown | Checked local context binds Kubernetes/Helm calls, including external timeout/xargs calls; purge and controller-bundle teardown refuse foreign instances of the CRDs they remove | Mocked rejection and context tests pass; real residue audit pending |
| Stage 2/3 certificate context bypass | Explicit context passed into a guarded certificate generator; Stage 3–7 use their own generator copies | Mocked certificate context/preservation and lookup-error tests pass; alternate-context real lifecycle pending |
| EBS ownership and hidden errors | Both cluster `owned` tag and Apollo PVC namespace are required; default dry-run; opt-in deletion rechecks state/ownership; API failures are nonzero | Mocked filter, no-delete, recheck, and failure propagation tests pass; no AWS operations performed |
| HTTPS mixed content | Canonical Stage 2 substage 5 through Stage 7 builds use HTTPS API URLs | Build arguments/values updated; real image/browser workflow pending |
| Broken TLS disable flag | HTTPS listener itself is conditional | Negative render checks pass across Stage 5–7 |
| Random/rendered certificates | No generated TLS Secret in Helm or Kustomize; stable externally provisioned `apollo-edge-tls` in Stage 5–7; explicit rotation | Deterministic render and no-TLS-Secret checks pass; live Argo convergence pending |
| Lost login verification | Token assertion restored; stronger trusted-HTTPS helper verifies login, populated search, booking, cancellation, and rejected hostname | CLI-mocked workflow/empty-result tests pass; actual HTTPS workflow pending |
| Token automount regression | All 13 application/data/seed ServiceAccounts disable automount in charts and bases | All 18 packaging renders verify the contract; actual Pods pending |
| Docs revision mismatch | Docs patch identifies base commit plus companion source patch, requiring rebuild; historical counts clearly scoped | Patch prepared and docs build passes; applying docs patch and publishing a verified immutable revision remain pending |
| Incorrect metrics and budget arithmetic | Real metric names/units; request-based budget and separate time-budget arithmetic | Edited docs build passes; example query results and Prometheus fixture execution pending |
| Incomplete performance baseline | Explicit cache switch; seeded routes; fixed arrival rate; warmup; populated-response/throughput/cache thresholds; reversible HPA/replica/cache guide | Go cache tests and Helm flag propagation pass; real k6 summaries pending |
| Stale status claims | READMEs/AGENTS label old counts historical; original audit marked historical; Stage 8 docs read the placeholder status | Prepared source/docs changes; lifecycle-based status promotion pending |
| Stage 6 learning progression | Baseline excludes observability; cumulative signal selector/lab and exact failure/recovery guide added | Helm/Kustomize selector regression checks pass; every substage runtime loop pending |
| Stage 6 booking SLO | Eligible booking POST success objective, 5m/1h/28d recordings, budget remaining, sustained burn alert, 30-day retention, bounded outage/recovery script and rule fixture | Renders parse; actual promtool evaluation and real outage/recovery pending |
| Stale SPEC | Entrypoint bootstrap, selected security tools, AWS/EKS plus GKE analysis, composite flight uniqueness, and Stage 7 k6 wording synchronized | Source review; no claim that planned security/cloud stages are implemented |
| GitOps ownership interaction | Shared PriorityClasses are platform-owned; tenant Applications disable their creation; tenant certificates are prepared by bootstrap | Static manifests and deterministic charts; live Argo reconciliation pending |

Stage 8–11 retain their approved planned status. Implementing those entire
missions is separate from correcting the defects above. An optional scope
question was offered; absent further steering, their planned status is retained. No completion of a planned
mission is claimed here.

## Completed checks

- 18 Python regression tests pass. The packaging test covers all 18 combinations
  of Stage 5/6/7, dev/staging/prod, and Helm/Kustomize. Other tests cover unsafe
  contexts, certificate preservation, foreign CRD instances, EBS deletion
  boundaries/failures, trusted-HTTPS CLI contracts, and empty-search rejection.
- Search's two Go cache-switch tests pass with `GOCACHE=/tmp/apollo11-go-build`.
- All 55 modified/added shell scripts pass `bash -n`.
- `git diff --check` passes in the source and prepared docs worktrees.
- The edited docs production build and TypeScript check pass from
  `/tmp/apollo11-docs-fixes`, without modifying the adjoining repository.
- Chart render output contains no TLS Secret, and repeated Helm renders are
  identical after certificate generation is removed from templates.

Evidence logs are beside this file. Static/isolated tests support the correction
boundaries above; they do not establish live lifecycle success.

## Why live checks remain pending

The sandbox cannot connect to `/var/run/docker.sock` and cannot open a socket to
the kind API at `127.0.0.1:6443`. k6 and promtool are unavailable. The filesystem
permits writes to Apollo11 and `/tmp`, but not to the adjoining docs repository.
These are environment limitations, not requests for additional task permission.
No unapproved cloud action or attempt to bypass these boundaries was made.

## Exact remaining verification sequence

1. Apply the docs patch in the adjoining repo; rebuild and typecheck there.
2. On a machine with Docker/kind access, isolate kubeconfig to the local cluster,
   build fresh images, and run one stage at a time. Preserve unrelated resources.
3. Re-prove Stage 2 substage 5 and Stage 3/4: trusted HTTPS helper, browser
   login/search/reversible booking, certificate deletion/recovery, then teardown.
4. Re-prove Stage 5–7 in Helm/dev and Kustomize/dev, then validate staging/prod
   contracts at their stated scope. Run their current verifier, manual failure
   experiments, and ownership/residue audit; record actual totals.
5. For Stage 6, install the baseline without observability, progress through
   all six signal substages, run their exact failure/recovery experiments, and
   prove one correlated booking. Run `scripts/slo-lab.sh` at substage 3.
6. Extract the PrometheusRule spec and execute the rule fixture:

   ```bash
   mkdir -p /tmp/apollo-slo
   helm template apollo11 stages/stage6/helm/apollo11 \
     --set gateway.envoy.bundleInstall=false --set metallb.bundleInstall=false \
     | python3 -c 'import yaml,sys; d=next(d for d in yaml.safe_load_all(sys.stdin) if d and d["kind"]=="PrometheusRule"); print(yaml.safe_dump(d["spec"],sort_keys=False))' \
     > /tmp/apollo-slo/rules.yaml
   cp test/stage6_slo_rules_test.yaml /tmp/apollo-slo/tests.yaml
   promtool test rules /tmp/apollo-slo/tests.yaml
   ```

7. Follow the Stage 7 benchmark guide, save both k6 summaries and environment
   records, prove the intended cache states and recovery, then run the HPA lab.
8. Bootstrap each Argo module against an authorized Git fixture containing the
   changes. Require converged Applications, stable certificate data on refresh,
   HTTPS workflows, isolated PriorityClass ownership, and clean teardown.
9. For AWS, retain the prototype boundary until a separately authorized real
   account lifecycle. Prove strict volume ownership, deletion error handling,
   and zero owned billable residue without touching unrelated account resources.
10. After an explicitly authorized commit and all relevant lifecycle gates,
    replace patch-based setup with its immutable revision and current evidence.

## Delivery

The source working tree contains the implemented changes. For a clean clone,
apply `apollo11-gap-fixes.patch` at the base commit above. In apollo11-docs at
`d041b64`, apply `apollo11-docs-gap-fixes.patch`. Both patches were checked against
their original bases. `DOCS_IMPROVEMENT_REPORT.md` contains the detailed teaching,
wording, organization, evidence, and maintenance recommendations.

The goal remains incomplete until the docs changes are applied and required
runtime evidence is obtained. No historical count was promoted into a claim
about this candidate.

## Follow-up completion audit

A second pass found and corrected ordinary Stage 6/7 teardown bypassing the
shared-CRD guard, Secret lookup errors being treated as absence, and benchmark
recovery discarding its saved HPA even after a failed restore. Two additional
regression tests cover the controller-bundle and Secret lookup failure paths.
The suite now passes 18 tests. The docs patch also repairs metric names/units
and ServiceMonitor selection in the other two observability chapters, replaces
a curl-in-Booking command that its image cannot run with a host port-forward,
and synchronizes the Launchpad/Ignition revision boundary. It now changes 16
pages. The actual adjoining worktree remains unchanged and clean.

Docker and kind access were rechecked and remain denied by the sandbox. The
previous goal turn made implementation and verification progress; this follow-up
also makes progress. The outstanding environment gates are unchanged, and the
goal is not marked complete.
