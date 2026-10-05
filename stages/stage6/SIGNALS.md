# Add one observability signal at a time

This is the ordered learning path. The existing full-stack installer remains
available for maintainer verification. The ordered path is implemented but
requires a clean runtime lifecycle before it replaces that verified snapshot.
Run from `stages/stage6`. Python 3 is needed for the standard-library manifest
selector; Helm or kubectl/Kustomize renders remain independently inspectable.

Build the baseline first with `bash scripts/apply.sh --without-observability`.
For a Kustomize comparison, add `--mode kustomize`. Confirm login and flight
search work before adding telemetry. This baseline intentionally has no
Prometheus Operator resources or signal collectors. Export `KUBE_CONTEXT` as
`kind-apollo11` or `kind-apollo11-dev`; all mutating scripts bind to it.

For each row below, render before applying:

```bash
bash scripts/signals-lab.sh render 1 helm > /tmp/apollo-metrics.yaml
bash scripts/signals-lab.sh apply 1 helm
```

Replace the number to progress through substages 1–6. Use `kustomize` for the
plain-manifest path. Progress cumulatively; teardown before returning to an
earlier substage. Substage 6 adds no new collector: it connects the signals
already installed. Use dev for this learning path; other environment renders
remain the full-stack packaging exercises.

| Substage | Build | Inspect and behavioral evidence | Safe break and recovery | Explain |
|---|---|---|---|---|
| 1. Metrics | Prometheus Operator, Prometheus, ServiceMonitors, discovery RBAC | Forward `service/prometheus` in `apollo-observability` to 19090; inspect `/api/v1/targets` and require five healthy application targets. Send search traffic, then query `rate(http_requests_total{service="search"}[2m])`. | Save a ServiceMonitor manifest, remove it, and observe its target disappear after discovery refresh. Restore the manifest and prove the target is UP and new request samples appear. | Why does a ServiceMonitor object alone not prove collection? |
| 2. Dashboards | Grafana and five dashboards | Forward Grafana to 13000; sign in using the lab credentials in values.yaml. Search requests must change the request-rate panel. Datasources for later signals may be configured before their endpoints exist; do not infer those signals are active. | Scale Grafana to zero; confirm the UI is unavailable while Prometheus still answers. Restore one replica and prove the UI and data return. | Which component stores metrics and which displays them? |
| 3. Alerts and SLO | PrometheusRule including booking-creation availability recordings | Use the SLO exercise below; query the error ratio, remaining budget, and alert state. | Remove Flight's replicas while generating valid booking attempts; observe 502 responses and budget consumption. Restore Flight and prove a booking succeeds, then cancel it. | Why are 4xx excluded, and why does no traffic not mean perfect availability? |
| 4. Logs | Loki and Alloy | Send a request with a unique `X-Request-ID`, query Loki for that value, and compare timestamps with the application log. | Temporarily exclude all nodes with a dedicated DaemonSet selector, and observe new log delivery stop. Remove the temporary scheduling change and prove a new request ID arrives. Never delete log PVCs. | Why do historical logs remaining searchable not prove current collection? |
| 5. Traces | Tempo and OpenTelemetry Collector | Run `bash scripts/trace-test.sh`. It creates and cancels a booking and requires a linked trace. | Save the Collector ConfigMap; temporarily change its Tempo exporter endpoint to an unused port, restart it, and observe export errors. Restore the ConfigMap, restart it, and prove a new booking trace arrives. | Which failure interrupts export without stopping the booking API? |
| 6. Correlation | Existing metrics, logs, and traces | Follow one booking by timestamp, request ID, and trace ID. Compare service-level metrics with its individual spans. | Repeat the collector failure above: metrics and logs should remain available while new traces fail. Recover and repeat the same workflow. | Why cannot an aggregate latency percentile identify one request's trace? |

Use a separate terminal for each port-forward. Endpoint checks require actual
response bodies, target samples, log entries, or traces; a Ready Pod alone is
not completion. Failure experiments are below, with explicit recovery commands.

## Exact signal failure commands

Always export `KUBE_CONTEXT=kind-apollo11` (or the supported dev context), then:

```bash
kube() { kubectl --context "$KUBE_CONTEXT" "$@"; }
```

Metrics discovery:

```bash
kube -n apollo-observability get servicemonitor search -o yaml > /tmp/search-monitor.yaml
kube -n apollo-observability delete servicemonitor search
# Observe Search disappear from /api/v1/targets, not just a missing object.
kube apply -f /tmp/search-monitor.yaml
# Send a new search and require UP plus advancing request samples.
```

Check the actual ServiceMonitor name with `kube -n apollo-observability get
servicemonitor` before the experiment; use its Search resource name if different.

Dashboard availability:

```bash
kube -n apollo-observability scale deployment/grafana --replicas=0
# Grafana should fail; curl http://localhost:19090/-/ready must still succeed.
kube -n apollo-observability scale deployment/grafana --replicas=1
kube -n apollo-observability rollout status deployment/grafana --timeout=120s
# Restart its port-forward and require /api/health plus a live metric panel.
```

Log delivery:

```bash
kube -n apollo-observability patch daemonset alloy --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"apollo11.io/log-break":"true"}}}}}'
# No node has this label. New requests must stop arriving in Loki.
kube -n apollo-observability patch daemonset alloy --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"apollo11.io/log-break":null}}}}}'
kube -n apollo-observability rollout status daemonset/alloy --timeout=120s
# Send another request ID and require it in Loki.
```

Trace export:

```bash
kube -n apollo-observability get configmap otel-collector-config -o yaml > /tmp/otel-original.yaml
sed 's/tempo.apollo-observability.svc.cluster.local:4317/tempo.apollo-observability.svc.cluster.local:1/' \
  /tmp/otel-original.yaml > /tmp/otel-broken.yaml
kube apply -f /tmp/otel-broken.yaml
kube -n apollo-observability rollout restart daemonset/otel-collector
# Send a booking; inspect Collector export errors and missing new trace.
kube apply -f /tmp/otel-original.yaml
kube -n apollo-observability rollout restart daemonset/otel-collector
kube -n apollo-observability rollout status daemonset/otel-collector --timeout=120s
bash scripts/trace-test.sh
```

If interrupted, run the matching recovery commands before continuing. Save
manifests outside the repository and remove those files after successful recovery.

## Booking availability SLO

The lab objective is **99.5% successful eligible booking-creation requests**.
Eligible means POST `/api/bookings` returning 2xx or 5xx; authentication and
validation errors are excluded. Failed requests returning 5xx consume a
request-based error budget. At zero traffic the ratio is absent, rather than
reported as 100% availability. Latency remains a separate histogram; its
millisecond bucket cannot identify whether the same request succeeded.

The recordings expose 5-minute, 1-hour, and 28-day error ratios, plus the
remaining budget `1 - error_ratio / 0.005`. Negative remaining budget means
overspending; it is not clamped away. Retention is 30 days, but a new local
cluster has only the history collected since installation. A two-minute drill
cannot prove a 28-day SLO. The burn alert compares both the short and long
observed windows against 14.4 times the allowed error rate, sustained for two
minutes. Inspect the Prometheus rule page for pending/firing state.

For an exact failure and automatic recovery, run:

```bash
bash scripts/slo-lab.sh
```

This preserves Flight's replica count, authenticates a passenger, chooses a
seeded flight, generates failed booking attempts during a Flight outage, then
restores Flight, creates and cancels a booking. It prints the observed error
ratio and budget after allowing for scrape/recording delay. The original
replica count is restored on exit. Read the script before running it: this is
an intentional, bounded outage in the local lab.

The Prometheus rule tests in `test/stage6_slo_rules_test.yaml` cover successful
requests, failures, and no traffic. Run them using `promtool test rules` against
the extracted rule groups, as described in `verification-runs/GAP_CLOSURE.md`.

Teardown with `bash scripts/teardown.sh --purge` (add `--mode kustomize` if that
was the baseline mode). Require the application and observability namespaces,
PVCs, controllers, and owned CRDs to be absent before starting another stage.
