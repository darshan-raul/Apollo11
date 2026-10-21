# Alert delivery, edge probes, and correlation

These additions extend the stage's Helm chart and generated Kustomize base.
Install using the stage README; historical verifier totals do not establish
these new behaviors. Alertmanager has ephemeral silence state and the local
receiver retains its last 100 payloads in memory. This is an inspection lab,
not durable incident storage. No external messaging account is required.

## Build and inspect

```bash
export KUBE_CONTEXT=kind-apollo11
kube() { kubectl --context "$KUBE_CONTEXT" "$@"; }
kube -n apollo-observability get deployments alertmanager alert-receiver blackbox
bash scripts/edge-probe.sh
```

The internal Probe checks the frontend Service. The edge script copies only the
public CA certificate into observability and creates a Probe targeting the
Gateway IP over HTTPS with the frontend hostname for SNI and HTTP routing.
The private key remains in the application namespace. Rerun after deliberate
certificate rotation or Gateway IP changes. This IP-targeted probe validates TLS
and routing; it does not test the learner workstation's DNS configuration.

Open separate terminals:

```bash
kube -n apollo-observability port-forward svc/prometheus 19090:9090
kube -n apollo-observability port-forward svc/alertmanager 19093:9093
kube -n apollo-observability port-forward svc/alert-receiver 18090:8080
```

In Prometheus, query `probe_success` and require both internal and edge series
to equal 1. `probe_ssl_earliest_cert_expiry` exposes the edge certificate expiry.
Missing series is a discovery problem, not a successful probe.

## Break, notify, silence, recover

Run `bash scripts/slo-lab.sh` on this stage’s installed snapshot. Observe pending → firing in Prometheus, then a firing
payload at `curl -fsS http://localhost:18090/`. Rule windows and evaluation delays
mean a short outage does not guarantee firing: keep the bounded lab duration
and inspect the actual alert state rather than assuming delivery.

In Alertmanager at `http://localhost:19093`, create a short silence matching the
specific alert name. Inspect its suppressed state. Expire the silence and
observe delivery resume if the alert is still firing. Recover Flight, create
and cancel a booking, then wait for rule windows to clear and require a
`resolved` payload at the local receiver. A Ready Alertmanager alone is not proof.

To break edge routing without deleting certificates, save the frontend HTTPRoute:

```bash
kube -n apollo-airlines-ui get httproute
# Use the frontend route name shown above in the next commands.
kube -n apollo-airlines-ui get httproute frontend -o yaml > /tmp/frontend-route.yaml
kube -n apollo-airlines-ui delete httproute frontend
# Require edge probe_success=0 while internal probe_success=1.
kube apply -f /tmp/frontend-route.yaml
# Require edge probe_success=1 and frontend HTTPS response again.
```

Restore the saved route immediately if interrupted. Teardown removes both
Probes and trust ConfigMap with the observability namespace.

## Follow one booking across signals

Run `bash scripts/trace-test.sh`. It creates and cancels a real booking, checks
its linked Tempo trace, and now polls Loki for the same trace ID. In Grafana
Explore, select Loki, expand that JSON log and click **View trace**. From its
Tempo span, follow **Logs** back to matching log lines. The datasource uses
JSON `trace_id` filtering with a two-minute time margin. Trace IDs remain parsed
fields, not high-cardinality Loki labels.

Break the Collector exporter using SIGNALS.md, generate a new request and show
that logs still arrive while its trace does not. Restore the exporter and prove
a new request links both ways. Historical logs/traces do not prove recovery.

Explain: why can healthy Pods coexist with failed edge access? How do alert
rules differ from notification routing? What does a silence suppress? Why is
trace ID useful for individual requests but unsuitable as a metric label?

References: [Alertmanager](https://prometheus.io/docs/alerting/latest/overview/),
[Blackbox modules](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md),
[Grafana correlation](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/configure-trace-to-logs/).

For automated edge break/recovery and notification delivery proof, run
`bash scripts/observability-lab.sh`. Its temporary synthetic alert isolates
delivery from SLO timing; it does not replace the booking SLO experiment.
