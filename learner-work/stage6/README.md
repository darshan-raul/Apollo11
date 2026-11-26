# Stage 6 — Author Before Bootstrap (Observability)

Before running `stages/stage6/scripts/apply.sh` to deploy the full Apollo Airlines observability stack, practice authoring the three Stage 6 observability primitives for the `flight` service: a **ServiceMonitor**, a **PrometheusRule** (recording rule + alert rules), and a **`promtool test rules`** unit test.

## Workspace Setup

Copy the starter manifests into `work/` (which is git-ignored) and edit the files inside `work/`:

```bash
mkdir -p learner-work/stage6/work
cp learner-work/stage6/starter/*.yaml learner-work/stage6/work/
```

## Requirements

Complete the three files in `learner-work/stage6/work/` so they satisfy the Stage 6 Prometheus discovery and telemetry contracts (`stages/stage6/helm/apollo11/templates/observability/`):

1. **`servicemonitor.yaml` (`ServiceMonitor`)**:
   - `apiVersion`: `monitoring.coreos.com/v1`, `kind`: `ServiceMonitor`
   - `metadata.name`: `flight`
   - `metadata.namespace`: `apollo-observability` (Prometheus `apollo` only watches `apollo-observability` via `serviceMonitorNamespaceSelector`)
   - `metadata.labels`: include `app.kubernetes.io/part-of: apollo-airlines` (required by Prometheus `serviceMonitorSelector`)
   - `spec.selector.matchLabels`: `app: flight`
   - `spec.namespaceSelector`: allow `apollo-airlines-apps` (`matchNames: [apollo-airlines-apps]` or `any: true`)
   - `spec.endpoints[0]`: `port: http`, `path: /metrics`

2. **`prometheusrule.yaml` (`PrometheusRule`)**:
   - `apiVersion`: `monitoring.coreos.com/v1`, `kind`: `PrometheusRule`
   - `metadata.name`: `flight-observability`
   - `metadata.namespace`: `apollo-observability`
   - `metadata.labels`: include `app.kubernetes.io/part-of: apollo-airlines` (required by Prometheus `ruleSelector`)
   - `spec.groups`: non-empty rule group(s) on the real Stage 6 `flight` metrics (`http_requests_total` and `http_request_duration_ms_bucket` in milliseconds):
     - Recording rule `apollo:flight_error_ratio:5m` computing the 5xx ratio over `2xx|5xx` requests (returning no sample when there is zero eligible traffic).
     - Alert rule `ApolloFlightErrorRateHigh` firing when `apollo:flight_error_ratio:5m > 0.05` (`for: 2m`, `labels: { severity: critical, service: flight }`).
     - Alert rule `ApolloFlightLatencyP95High` using `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_ms_bucket{service="flight"}[5m]))) > 250` (`for: 2m`, `labels: { severity: warning, service: flight }`).

3. **`rules_test.yaml` (`promtool test rules`)**:
   - `rule_files: [rules.yaml]`
   - `evaluation_interval: 30s`
   - `fuzzy_compare: true`
   - `tests:` containing both `promql_expr_test` (verifying `apollo:flight_error_ratio:5m`) and `alert_rule_test` (verifying `ApolloFlightErrorRateHigh` and `ApolloFlightLatencyP95High` fire under synthetic failure/latency series).

> **Note:** `promtool test rules` evaluates raw Prometheus rule groups (`spec.groups`) rather than a Kubernetes `PrometheusRule` wrapper. `check.sh` extracts `prometheusrule.yaml`'s `.spec` into a temporary `rules.yaml` automatically before running `promtool test rules`.

## Validate Your Work

Run the offline verifier against your `work/` directory:

```bash
bash learner-work/stage6/check.sh
```

You can also pass any directory explicitly, or verify the reference solution:

```bash
bash learner-work/stage6/check.sh learner-work/stage6/work
bash learner-work/stage6/check.sh --solution
```

Once `check.sh` passes, return to `stages/stage6/README.md` and run `bash stages/stage6/scripts/apply.sh --mode helm --env dev` (or `--without-observability` for the ordered signal path in `stages/stage6/SIGNALS.md`).
