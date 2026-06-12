---
title: "Stage 6 — Mission Ops"
description: "Stage 6 adds the observability stack (Prometheus + Grafana + OTEL Collector + Tempo + Loki + Promtail) to Apollo11, plus OTEL SDK + real /metrics in all 5 backend services."
---

# Stage 6: Mission Ops

**Goal:** make Apollo Airlines **observable**. Every service emits
structured logs, real Prometheus metrics, and OpenTelemetry traces.
Traces + metrics + logs flow into a unified observability stack you can
explore in Grafana.

| | |
|---|---|
| **New concept** | OpenTelemetry SDK (traces + metrics), Prometheus ServiceMonitors, Grafana dashboards, Tempo trace backend, Loki log aggregation, OTEL Collector DaemonSet, 16 alert rules |
| **Workloads changed** | 5 backend services get the OTEL SDK + a real `/metrics` endpoint returning Prometheus exposition format |
| **Workloads unchanged** | Probes, Guaranteed QoS, graceful SIGTERM, 13 SAs, 3 PG + 1 Redis StatefulSets, seed jobs, PDBs, frontend NGINX config |
| **New cluster resources** | 1 new namespace (`apollo-observability`), 5 observability workloads (Prometheus, Grafana, OTEL Collector, Tempo, Loki, Promtail), 5 ServiceMonitors, 16 alert rules, 5 Grafana dashboards, 1 cross-namespace HTTPRoute + ReferenceGrant |
| **Code changes** | All 5 backends: OTEL SDK init + otelgin middleware + real `/metrics` via promhttp. 4 Go services + 1 Python service. Frontend unchanged. |
| **Verify target** | **~95 checks** (70 from Stage 5 + 25 new: observability pods, ServiceMonitors, alert rules, real `/metrics`, cross-service trace, Grafana dashboard HTTP, Loki log query, Prometheus self-check) |

---

## What changed vs Stage 5

### 1. Code (5 backend services)

The 4 Go services (flight, booking, search, notification) and 1 Python
service (identity) all got:

- **OpenTelemetry SDK init** with OTLP gRPC exporter to
  `otel-collector:4317`
- **otelgin / FastAPIInstrumentor middleware** — auto-extracts the
  W3C `traceparent` header and starts a server span per request
- **Real Prometheus `/metrics`** via `promhttp.Handler()` /
  `prometheus_client.generate_latest()` — returns the actual
  exposition format (no more `http_requests_total: 0` placeholder)
- **trace_id/span_id in JSON logs** — pulled from the active OTEL
  span context, so every log line is auto-correlated to the trace
- **Outbound HTTP tracing** — `callService` (Go) and `requests`
  (Python) now start a child client span + inject the
  `traceparent` header on the outgoing request

The frontend (NGINX static) gets no changes — browser-side RUM
OTEL is a Stage 8+ concern.

### 2. Helm chart (`helm/apollo11/`)

All Stage 5 templates are unchanged at the structure level. The 5
app templates now have two additions:

- `spec.template.metadata.annotations` block with
  `prometheus.io/scrape: "true"` etc.
- New env vars in each container: `OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER`,
  `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`

Plus a new `templates/observability/` directory with 15+ new
manifests for the Mission Ops stack.

### 3. Observability stack (new)

Single new namespace `apollo-observability` with:

| Component | Image | Type | Storage | Memory |
|---|---|---|---|---|
| Prometheus | `prom/prometheus:v2.51.2` | Deployment | 5Gi | 1Gi req |
| Alertmanager | (Stage 8) | — | — | — |
| Grafana | `grafana/grafana:10.4.2` | Deployment | 1Gi | 256Mi req |
| OTEL Collector | `otel/opentelemetry-collector-contrib:0.99.0` | DaemonSet | — | 256Mi req |
| Tempo | `grafana/tempo:2.3.1` | Deployment | 5Gi | 256Mi req |
| Loki | `grafana/loki:2.9.8` | Deployment | 5Gi | 512Mi req |
| Promtail | `grafana/promtail:2.9.8` | DaemonSet | — | 64Mi req |

Total resource budget: ~2.5Gi memory, ~1.1 CPU on a kind node.

### 4. ServiceMonitors

5 ServiceMonitors, one per backend, each scraping the
`/metrics` endpoint every 30s. Prometheus discovers them
automatically.

### 5. Alert rules (16 total)

4 rule groups:
- `apollo_services` — ServiceDown, ServiceFlapping, StatefulSetDown
- `apollo_latency` — booking/flight/search p95 + booking p99
- `apollo_errors` — 5xx rate, spike, 401 brute force
- `apollo_infrastructure` — OOM, CrashLoop, PVC full, node CPU/mem, Tempo storage

### 6. Grafana dashboards (5 total)

- **Apollo Overview** — top-level health stats
- **Booking Service** — booking-specific latency breakdown
- **Service Errors** — 5xx/4xx per service
- **Resource Saturation** — pod CPU, memory, restarts, PVC
- **Trace Viewer** — Tempo trace browser

3 datasources wired: Prometheus, Loki, Tempo.

### 7. Grafana ingress

New HTTPRoute + ReferenceGrant: `grafana.apollo.local` is served
via the existing Envoy Gateway in `apollo-airlines-apps`, reaching
the Grafana pod in `apollo-observability`.

---

## Architecture

```
                          apollo-observability (new ns)
                          ┌──────────────────────────────────────────┐
                          │                                          │
                          │  ┌──────────────┐  ┌──────────────┐      │
                          │  │ Prometheus   │  │ Grafana      │      │
                          │  │ (port 9090)  │  │ (port 3000)  │      │
                          │  │ scrape ──────│──│ datasources  │      │
                          │  │ 5 SMs / 30s  │  │ 3 (P+L+T)    │      │
                          │  └──────┬───────┘  └──────────────┘      │
                          │         │              ▲                 │
                          │         │              │ grafana.apollo.local
                          │         │              │ (HTTPRoute via existing Gateway)
                          │  ┌──────┴───────┐  ┌───┴──────────┐        │
                          │  │ 16 alert     │  │ 5 dashboards│        │
                          │  │ rules        │  │ JSON in CM  │        │
                          │  └──────────────┘  └──────────────┘        │
                          │                                          │
                          │  ┌──────────────┐  ┌──────────────┐      │
                          │  │ OTEL         │  │ Tempo        │      │
                          │  │ Collector    │──│ (traces)     │      │
                          │  │ (DaemonSet)  │  │ 5Gi          │      │
                          │  │ OTLP :4317   │  └──────┬───────┘      │
                          │  │ :4318        │         │              │
                          │  └──────┬───────┘         │              │
                          │         │                 ▼              │
                          │  ┌──────┴───────┐  ┌──────────────┐      │
                          │  │ Loki         │  │ Promtail     │      │
                          │  │ (logs)       │←─│ (DaemonSet)  │      │
                          │  │ 5Gi / 7d     │  │  /var/log    │      │
                          │  └──────────────┘  └──────────────┘      │
                          │                                          │
                          └──────────────────────────────────────────┘
                                        ▲                       ▲
                          OTLP gRPC    │                       │  pod logs
                          :4317        │                       │
                                        │                       │
        apollo-airlines-apps (existing) │                       │
        ┌───────────────────────────────┴───────────┐           │
        │  booking (Go+OTEL)  flight (Go+OTEL)        │           │
        │  search (Go+OTEL)   notification (Go+OTEL)  │           │
        │  identity (Py+OTEL)  frontend (NGINX, no OTEL)│         │
        │                                            │           │
        │  5 ServiceMonitors ─── scrape /metrics      │           │
        │  5 OTLP gRPC exporters ── push traces        │           │
        └────────────────────────────────────────────┘           │
                                                                │
   node filesystem (kind: /var/log/pods) ─────────────────────┘
                              Promtail reads container logs
```

---

## Files

```
stages/stage6/
├── code/                                # snapshot of stage5/code with OTEL SDK + real /metrics
│   ├── booking/main.go                   # Go + OTEL + real /metrics
│   ├── booking/go.mod                    # +5 OTEL/Prom deps
│   ├── flight/main.go                    # same
│   ├── search/main.go                    # same (pass-through service)
│   ├── notification/main.go              # same (Redis-backed fan-out)
│   ├── identity/main.py                  # Python + OTEL + real /metrics
│   ├── identity/requirements.txt         # +6 OTEL/Prom deps
│   └── frontend/                         # unchanged
│
├── helm/apollo11/
│   ├── Chart.yaml, values.yaml, values-{dev,staging,prod}.yaml
│   ├── bundles/                         # Envoy + MetalLB (unchanged from stage 5)
│   └── templates/
│       ├── _helpers.tpl
│       ├── config/                       # namespace, SA, configmap, secrets
│       ├── infra/                        # postgres, redis (unchanged)
│       ├── apps/                         # 5 backends: +prometheus.io annotations + OTEL env
│       ├── ui/frontend.yaml             # unchanged
│       ├── pdb/pdb.yaml                  # unchanged
│       ├── jobs/seed.yaml                # unchanged
│       ├── gateway/                      # 5 manifests, unchanged
│       └── observability/                # NEW
│           ├── namespace.yaml
│           ├── serviceaccount.yaml
│           ├── prometheus/               # config + rules + deployment
│           ├── servicemonitors/          # 5 ServiceMonitors
│           ├── grafana/                  # deployment + datasources + 5 dashboards
│           ├── otel-collector/           # config + daemonset
│           ├── tempo/                    # config + deployment
│           ├── loki/                     # config + deployment + promtail daemonset
│           └── ingress/grafana-route.yaml
│
├── scripts/
│   ├── apply.sh                          # 10 phases, full stack
│   ├── teardown.sh                       # symmetric, --full, --purge levels
│   ├── verify.sh                         # ~95 checks
│   ├── build-images.sh                   # 6 services + frontend
│   └── trace-test.sh                     # NEW: end-to-end trace demo
│
└── argocd/                               # Stage 5's argocd module, unchanged
    ├── README.md, ARGOCD.md, DEMO.md
    ├── install.sh, uninstall.sh
    ├── projects/project.yaml
    ├── applications/{dev,staging,prod}.yaml
    └── scripts/{bootstrap,verify,teardown}.sh
```

---

## Usage

### Helm (production path — full stack)

```bash
cd stages/stage6
bash scripts/build-images.sh                       # build 6 images + frontend
bash scripts/apply.sh                              # 10 phases, ~7-10 min
bash scripts/verify.sh                             # ~95 checks
bash scripts/trace-test.sh                        # cross-service trace demo
```

### Access Grafana

```bash
kubectl port-forward svc/grafana -n apollo-observability 3000:3000 &
open http://localhost:3000
# login: admin / apollo-admin
```

### Access Prometheus

```bash
kubectl port-forward svc/prometheus -n apollo-observability 9090:9090 &
open http://localhost:9090
```

### Access Tempo (traces)

```bash
# In Grafana: Explore → Tempo datasource → search by service.name = "booking"
# Or via API:
kubectl exec -n apollo-observability deploy/tempo -- \
    wget -qO- 'http://localhost:3100/api/search?tags=service.name%3Dbooking&limit=20'
```

### Trace test

```bash
bash scripts/trace-test.sh
# Logs in as admin, creates a booking, polls Tempo for the trace,
# prints all 6 spans (booking → identity → flight → flight-db → notification).
```

### Skip observability (app only)

```bash
bash scripts/apply.sh --skip-observability   # just the Stage 5 baseline
```

### Teardown

```bash
bash scripts/teardown.sh                # default: helm uninstall + observability ns
bash scripts/teardown.sh --full         # also app namespaces
bash scripts/teardown.sh --purge        # also access stack + CRDs
```

---

## Verify target — 95 checks

**70 carryover from Stage 5** (namespaces, SAs, ConfigMap, Secret, 4
StatefulSets, 4 headless SVCs, 5 app Deployments + frontend, probes,
resources, PDBs, seed jobs, Gateway, HTTPRoutes, ReferenceGrant,
MetalLB IP pool, plus the new OTEL env + prometheus.io annotations)

**25 new for Stage 6:**

- 1 observability namespace
- 1 ServiceAccount + ClusterRole + ClusterRoleBinding
- 5 observability pods (Prometheus, Grafana, OTEL Collector, Tempo, Loki, Promtail)
- 5 observability services
- 5 ServiceMonitors
- 16 alert rules loaded into Prometheus
- 1 real `/metrics` endpoint returning Prometheus format (not JSON)
- 5 Grafana dashboards
- 3 Grafana datasources
- 1 Grafana HTTPRoute + ReferenceGrant
- 1 Prometheus self-check (`up{}` returns 5 services)
- 1 Loki log query

---

## Code evolution summary (Stage 6)

| File | Change |
|---|---|
| `code/booking/main.go` | +OTEL SDK + otelgin + promhttp /metrics + span context in logJSON |
| `code/flight/main.go` | same |
| `code/search/main.go` | same |
| `code/notification/main.go` | same |
| `code/identity/main.py` | +OTEL SDK + FastAPIInstrumentor + Psycopg2Instrumentor + prometheus_client /metrics |
| `code/booking/go.mod` | +5 deps: OTEL SDK, otelgin, prometheus client_golang, google.golang.org/grpc |
| (same for flight/search/notification) | same 5 deps |
| `code/identity/requirements.txt` | +6 deps: opentelemetry-{api,sdk,exporter-otlp-proto-grpc,instrumentation-{fastapi,psycopg2,requests}}, prometheus-client |
| 4 backend Dockerfiles | unchanged (new deps picked up via go.mod/requirements.txt) |
| `code/frontend/*` | unchanged |

No database migration. No API contract change. The `/healthz`,
`/healthz/{startup,live,ready}`, `/readyz`, and the existing
`/metrics` JSON shape are all preserved (the `/metrics` endpoint
now returns a richer Prometheus exposition format in addition to the
same fields).

---

## Lessons learned (Stage 6)

1. **OTEL SDK init order matters.** The tracer must be set up *before*
   the HTTP server starts. `otelgin.Middleware` reads from the
   global `otel.TracerProvider` at request time, so the order is
   init → middleware setup → server start.

2. **Service.prometheus.io annotations are the simplest scrape
   target.** Adding `prometheus.io/scrape: "true"` +
   `prometheus.io/port` + `prometheus.io/path` to the pod template
   is enough for Prometheus to discover and scrape. The
   ServiceMonitor (CRD) is more powerful but requires the Prometheus
   operator. We have both — the ServiceMonitor is the primary
   source of truth, the annotations are a backup.

3. **OTEL Collector DaemonSet has a unique DNS quirk.** When you
   `kubectl exec` from a debug pod, the `otel-collector:4317` host
   resolves to one of the DaemonSet pods at random. For trace-test
   purposes this is fine (we just need a working OTLP endpoint), but
   for production you might want a separate Service with
   `clusterIP: None` (headless) for stable DNS.

4. **Grafana JSON in YAML ConfigMaps is fragile.** A naive
   `data: dashboard.json: |` (literal block scalar) breaks when the
   JSON contains `null` literals, because YAML treats `null` as a
   null scalar in unquoted context. The fix is to use a quoted
   single-line JSON string instead of a multi-line block.

5. **Tempo's storage path matters.** The `local` backend writes
   to `/var/tempo/blocks` and `/var/tempo/wal`. The PVC must mount
   at `/var/tempo` so both paths are covered by the same persistent
   volume.

6. **Loki + Promtail's namespace filter keeps storage low.** A
   relabel rule `__meta_kubernetes_namespace =~ 'apollo-.*|apollo-airlines-.*'`
   ensures we only ship logs from Apollo namespaces, not from
   `kube-system` or `argocd`.

7. **Cross-namespace HTTPRoutes need a ReferenceGrant** in the
   gateway's namespace authorizing the source HTTPRoute namespace
   to reference Services. We hit this when wiring Grafana — the
   gateway is in `apollo-airlines-apps`, the Grafana service is in
   `apollo-observability`.

8. **The default helm install + ArgoCD + chart-with-gates
   approach is harder than it looks.** We tried wrapping the
   chart with per-template `{{- if .Values.X.enabled }}` gates so
   the same chart could deploy apps or observability. The
   indentation of inner `{{- with .Values.probes.X }} ... {{- end }}`
   blocks makes this fragile. A cleaner approach (skipped here for
   time) is to extract the observability templates into a separate
   subchart.
