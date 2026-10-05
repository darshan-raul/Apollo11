---
title: "Stage 6 — Mission Ops"
description: "Instrument Apollo Airlines with Prometheus metrics, OpenTelemetry traces, Grafana dashboards, and Loki logs."
---

> **Current verification status:** the context, TLS, and contract fixes in this
> working tree require a fresh runtime lifecycle. Counts below record earlier
> revisions; use the current verifier's summary rather than expecting those totals.

# Stage 6: Mission Ops

Stage 6 makes the Stage 5 application observable without changing its public
API. The five backend services expose real Prometheus metrics, propagate W3C
trace context, and export traces through an OpenTelemetry Collector. Grafana
brings Prometheus metrics, Tempo traces, and Loki logs together.

**Status:** Complete and fresh-cluster verified on 2026-08-25.

| Delivery path | Evidence |
|---|---|
| Helm/dev | **190/190** checks passed, followed by a clean purge |
| Kustomize/dev | **180/180** checks passed, followed by a clean purge |
| Argo CD | Four-Application layout statically validated: dev 58, staging 58, prod 60, shared observability 34 resources |

The hosted CI run, image publication, and live Argo reconciliation remain
external checks: they require a push or a Git revision containing this work.

## What changed from Stage 5

### Application telemetry

The identity, flight, booking, search, and notification services now provide:

- real `http_requests_total` counters and request-duration histograms at
  `/metrics`;
- OpenTelemetry server spans and instrumented outbound HTTP calls;
- W3C `traceparent` propagation across service boundaries;
- `trace_id` and `span_id` correlation in structured JSON logs; and
- OTLP export to the collector at
  `otel-collector.apollo-observability.svc.cluster.local:4317`.

The booking flow produces one trace spanning booking, identity, flight, and
notification. Its downstream calls preserve authentication and parent trace
context. The frontend remains an NGINX-served SPA; browser RUM is outside this
stage.

### Observability platform

The `apollo-observability` namespace contains:

| Component | Image | Role |
|---|---|---|
| Prometheus | `quay.io/prometheus/prometheus:v3.13.1` | Scrapes five ServiceMonitors and evaluates Apollo alert rules |
| Grafana | `grafana/grafana:10.4.2` | Five provisioned dashboards and Prometheus/Loki/Tempo datasources |
| OpenTelemetry Collector | `otel/opentelemetry-collector-contrib:0.99.0` | Per-node OTLP receiver and trace pipeline |
| Tempo | `grafana/tempo:2.3.1` | Trace storage and query API |
| Loki | `grafana/loki:2.9.8` | Kubernetes log storage and query API |
| Alloy | `grafana/alloy:v1.18.0` | Per-node Kubernetes log collection; replaces end-of-life Promtail |

Prometheus is managed by Prometheus Operator v0.93.0. Its CRDs and controller
are installed from `bundles/prometheus-operator-v0.93.0.yaml`, outside the Helm
chart. Keeping the large operator bundle outside the chart prevents Helm's
release Secret from exceeding Kubernetes' 1 MiB object limit.

Grafana is available through the existing Envoy Gateway at
`grafana.apollo.local`. The cross-namespace HTTPRoute is authorized by a
ReferenceGrant.

## Packaging

Stage 6 keeps both Stage 5 delivery paths:

- `helm/apollo11/` is the configurable Helm chart.
- `overlays/base/generated.yaml` is a complete plain-manifest base, so
  Kustomize does not depend on Helm at runtime.
- `overlays/dev`, `overlays/staging`, and `overlays/prod` apply environment
  replica, image, and PDB policy.

The Argo CD module uses four Applications. Dev, staging, and prod own their
tenant workloads with chart observability disabled. The
`apollo11-observability` Application owns the shared namespace and platform
resources once, avoiding collisions between environments.

## Run the lab

Use the kind cluster created in Ignition, then run from this directory.

### Helm

```bash
bash scripts/apply.sh --mode helm --env dev
bash scripts/verify.sh --mode helm
bash scripts/teardown.sh --mode helm --env dev --purge
```

### Kustomize

```bash
bash scripts/apply.sh --mode kustomize --env dev
bash scripts/verify.sh --mode kustomize
bash scripts/teardown.sh --mode kustomize --env dev --purge
```

`apply.sh` builds and loads the local service images unless its documented
skip-build option is used. Both modes install Envoy Gateway, MetalLB, and the
Prometheus Operator before applying the Stage 6 resources.

## Explore the signals

Grafana through Envoy:

```bash
ENVOY_IP=$(kubectl get service -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl -H 'Host: grafana.apollo.local' "http://${ENVOY_IP}/api/health"
```

Grafana login: `admin` / `apollo-admin`.

Run the distributed-trace demonstration:

```bash
bash scripts/trace-test.sh
```

The script logs in as the seeded passenger, creates a valid booking, captures
its trace ID, and polls Tempo until booking, identity, flight, and notification
are present. It then cancels the booking and verifies the internal seat-restore
path succeeds.

For direct local access:

```bash
kubectl port-forward -n apollo-observability service/prometheus 9090:9090
kubectl port-forward -n apollo-observability service/grafana 3000:3000
```

## Verification coverage

`scripts/verify.sh` checks the complete inherited workload contract plus the
new observability behavior. Among other checks, it proves that:

- the operator CRDs, Prometheus custom resource, five ServiceMonitors, and
  alert rules are functional;
- each backend exposes changing counters and a latency histogram;
- all observability Deployments and both DaemonSets are ready;
- Prometheus has at least five healthy Apollo targets;
- Grafana, Tempo, and Loki APIs respond;
- Grafana is reachable through Envoy and MetalLB;
- one booking trace reaches all four participating services in Tempo;
- Alloy delivers Apollo Kubernetes logs to Loki; and
- all Stage 5 probes, resources, storage, seed data, routes, and login behavior
  remain intact.

## Key implementation lessons

1. A `ServiceMonitor` is inert without an operator and a Prometheus resource
   selecting it. Stage 6 owns the entire lifecycle, including teardown of the
   CRDs when `--purge` is requested.
2. Namespace selectors use the standard
   `kubernetes.io/metadata.name` label; a made-up `name` label silently selects
   nothing.
3. The Prometheus Service must target the container's actual named port
   (`web`). A healthy Pod alone does not prove that the Service is routable.
4. Trace context must be passed into every downstream request. Creating those
   requests from a background context breaks the trace even when each service
   is individually instrumented.
5. Alloy replaces Promtail, whose lifecycle ended before this stage was
   finalized. It tails only Apollo namespaces to keep the local lab compact.
6. Tempo configuration is version-sensitive. This stage uses only fields
   accepted by the pinned Tempo 2.3.1 image.

## Source layout

```text
stages/stage6/
├── bundles/                         # Prometheus Operator install bundle
├── code/                            # self-contained instrumented service snapshot
├── helm/apollo11/                   # full Helm packaging
├── overlays/{base,dev,staging,prod} # Helm-free Kustomize packaging
├── scripts/                         # build, apply, verify, trace-test, teardown
└── argocd/                          # project + four Applications + validation
```

## Local HTTPS and certificate ownership

The canonical Gateway offers HTTP on port 80 and HTTPS on port 443. Frontend
API URLs are now baked as HTTPS; rebuild images before switching snapshots.
The certificate Secret is generated at installation time and preserved across
reapplication. It is not part of Helm release ownership or the Kustomize base.
Use `bash scripts/generate-certs.sh --rotate` to renew it deliberately.

Export `KUBE_CONTEXT=kind-apollo11` (or `kind-apollo11-dev`) before using the
scripts. For a manual Helm/Kustomize install, create both application namespaces
and run the certificate generator before submitting Gateway resources. Argo CD
bootstrap prepares separate certificates in each tenant's namespaces.

Extract the public certificate, then check the actual DNS hostname and trust:

```bash
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get secret apollo-edge-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/apollo-ca.crt
gateway_ip=$(kubectl --context "$KUBE_CONTEXT" -n envoy-gateway-system get service \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl --cacert /tmp/apollo-ca.crt --resolve "identity.apollo.local:443:$gateway_ip" \
  https://identity.apollo.local/healthz
```

Add the Gateway address and all five hostnames to local name resolution before
using the browser. Trust the local certificate using your browser/OS's local
certificate facility, then open `https://frontend.apollo.local`. Verify login,
flight search, and a reversible booking in the browser's Network panel: all API
requests must use HTTPS. A successful HTML response alone does not establish
that behavior. `curl -k` skips trust verification and is only a diagnostic.

Delete the apps-namespace certificate to break the HTTPS listener. HTTP should
remain available. Re-run the certificate generator and require a trusted HTTPS
response plus login/search recovery. If the old certificate was deleted,
extract the replacement and update local trust. Teardown removes the runtime
certificate when it deletes the owned namespace.

Follow [the ordered signal labs](SIGNALS.md) for metrics → dashboards → alerts/SLO → logs → traces → correlation.
