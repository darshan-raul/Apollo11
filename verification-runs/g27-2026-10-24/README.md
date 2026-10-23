---
title: "G27 — Stage 6 ordered signal path, live (2026-10-24)"
description: "Baseline without observability, then signals-lab substages 1–6 applied in order, each with its SIGNALS.md break and recovery checked through real responses."
---

# G27 — Stage 6 ordered signal path, live (2026-10-24)

Code: Apollo11 `90b5120` plus the uncommitted SIGNALS.md fixes below. Cluster:
`kind-apollo11`. The harness (kept outside the repo) ran
`apply.sh --mode helm --env dev --without-observability`, then
`signals-lab.sh apply N helm` for N = 1…6 in order, checking each substage
from a temporary in-cluster curl Pod, and finally `teardown.sh --purge`.

## Final run (`run.log`): 34 passed, 1 failed

| Substage | Inspect | Break → recover |
|---|---|---|
| Baseline | no observability workloads; flight API 200 | – |
| 1 Metrics | 5 healthy Apollo targets in Prometheus | delete search ServiceMonitor → target gone → re-run `apply 1` → target UP |
| 2 Dashboards | Grafana `/api/health` 200 | scale Grafana to 0 → UI down while Prometheus ready → scale 1 → 200 |
| 3 Alerts/SLO | 4 `apollo:booking_*` recording rules loaded | `slo-lab.sh`: Flight outage, budget burn, recovery booking: pass |
| 4 Logs | a unique query-string marker found in Loki | Alloy unscheduled → new marker absent, old marker still searchable → restored → new marker present |
| 5 Traces | **FAIL** on the first `trace-test.sh`: the trace lacked booking's spans | exporter pointed at a dead port in place → no new trace while booking, logs and metrics keep working → re-run `apply 5` restores `:4317` → new trace complete |
| 6 Correlation | `trace-test.sh`: trace in Tempo and its `trace_id` in Loki | `observability-lab.sh` passes; full `verify.sh --mode helm` passes on the cumulative install |
| Teardown | – | no Apollo, Envoy or MetalLB namespaces |

The one failure is a warm-up race, not a broken path. The services start in the
baseline with no Collector, so their OTLP exporters are in reconnect backoff
when substage 5 adds one. The first booking's trace arrived without booking's
spans; every later trace in the run was complete. In the previous attempt the
same check passed the first time. SIGNALS.md now tells learners to rerun once if
the first trace is incomplete.

## Defects found and fixed during G27

1. **Restoring from a live-object dump breaks the next substage.** SIGNALS.md
   restored the ServiceMonitor (and the Collector ConfigMap) by reapplying a
   `kubectl get -o yaml` dump. That stores `resourceVersion`/`uid` in the
   last-applied annotation, and the next `signals-lab.sh apply` failed with
   "metadata.resourceVersion: Invalid value: 0" (first attempt, archived in
   `/tmp`, not committed). SIGNALS.md now restores by re-running the current
   substage's `signals-lab.sh apply` and breaks the ConfigMap in place with
   `kubectl replace`. Both were exercised in the final run. The same pattern in
   OBSERVABILITY.md is tracker G33.
2. **Stage 6 logs no longer contain the X-Request-ID** (tracker G34). The second
   attempt (`attempt-request-id-marker/`, 31 passed, 4 failed) followed
   SIGNALS.md literally and never found a request ID in Loki, because Stage 6
   replaced the request ID in `trace_id` with the OTEL trace ID. Every one of its
   4 failures is this. SIGNALS.md now uses a query-string marker, which flight's
   GIN access log records.

The first attempt was also interrupted by an overlapping manual `signals-lab.sh`
run of mine; it was discarded, not used as evidence.
