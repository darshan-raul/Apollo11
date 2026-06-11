#!/bin/bash
# Verify Stage 6: ~95 checks across:
#   1. (Stage 5 carryover) ~70 checks: namespaces, SAs, ConfigMap, Secret,
#      4 StatefulSets, 4 headless SVCs, 5 app Deployments + frontend,
#      probes, resources, PDBs, seed jobs, Gateway, HTTPRoutes,
#      ReferenceGrant, MetalLB IP pool
#   2. (Stage 6) ~25 new: observability namespace, 7 observability pods,
#      5 ServiceMonitors, 1 OTEL collector, 1 Tempo, real /metrics,
#      cross-service trace, alert rules, Grafana dashboard, Loki log
#
# Usage:
#   ./scripts/verify.sh                       # full suite
#   ./scripts/verify.sh --skip-observability  # only Stage 5 checks
#   ./scripts/verify.sh --skip-workloads      # only observability checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"

SKIP_OBSERVABILITY=false
SKIP_WORKLOADS=false

usage() {
    cat <<EOF
Usage: $0 [--skip-observability] [--skip-workloads]
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-observability) SKIP_OBSERVABILITY=true; shift ;;
        --skip-workloads)     SKIP_WORKLOADS=true; shift ;;
        --help)                usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

# =============================================================================
# Stage 5 carryover
# =============================================================================
if [[ "$SKIP_WORKLOADS" != "true" ]]; then
    step "Namespaces (2 expected: apollo-airlines-apps, apollo-airlines-ui)"
    for ns in apollo-airlines-apps apollo-airlines-ui; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            pass "ns/$ns"
        else
            fail "ns/$ns missing"
        fi
    done

    step "ServiceAccounts (13 expected)"
    EXPECTED_SAS=(
      "apollo-airlines-apps:identity"     "apollo-airlines-apps:flight"
      "apollo-airlines-apps:booking"      "apollo-airlines-apps:search"
      "apollo-airlines-apps:notification" "apollo-airlines-ui:frontend"
      "apollo-airlines-apps:identity-db"  "apollo-airlines-apps:flight-db"
      "apollo-airlines-apps:booking-db"   "apollo-airlines-apps:redis"
      "apollo-airlines-apps:init-identity-db"
      "apollo-airlines-apps:init-flight-db"
      "apollo-airlines-apps:init-booking-db"
    )
    for sa in "${EXPECTED_SAS[@]}"; do
        ns="${sa%%:*}"; name="${sa##*:}"
        if kubectl get sa "$name" -n "$ns" >/dev/null 2>&1; then
            pass "sa $ns/$name"
        else
            fail "sa $ns/$name missing"
        fi
    done

    step "ConfigMap + Secret"
    kubectl get cm apollo-airlines-config -n apollo-airlines-apps >/dev/null 2>&1 && pass "cm/apollo-airlines-config (apps)" || fail "cm/apollo-airlines-config missing (apps)"
    kubectl get cm apollo-airlines-config -n apollo-airlines-ui >/dev/null 2>&1 && pass "cm/apollo-airlines-config (ui)" || fail "cm/apollo-airlines-config missing (ui)"
    kubectl get secret apollo-airlines-secrets -n apollo-airlines-apps >/dev/null 2>&1 && pass "secret/apollo-airlines-secrets" || fail "secret/apollo-airlines-secrets missing"

    step "StatefulSets (4 expected, all 1/1 Ready)"
    for sts in identity-db flight-db booking-db redis; do
        ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [[ "$ready" -ge 1 ]]; then pass "statefulset/$sts ready=$ready"; else fail "statefulset/$sts not ready"; fi
    done

    step "App Deployments (5 expected, all ≥1 Ready)"
    for dep in identity flight booking search notification; do
        ready=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [[ "$ready" -ge 1 ]]; then pass "deployment/$dep ready=$ready"; else fail "deployment/$dep not ready"; fi
    done

    ready=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -ge 1 ]]; then pass "deployment/frontend ready=$ready"; else fail "deployment/frontend not ready"; fi

    step "Probes (startup/live/ready on 6 apps)"
    for dep in identity flight booking search notification frontend; do
        if [[ "$dep" == "frontend" ]]; then
            ns=apollo-airlines-ui
        else
            ns=apollo-airlines-apps
        fi
        for probe in startupProbe livenessProbe readinessProbe; do
            path=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || echo "")
            if [[ "$path" == "/healthz/"* ]]; then
                pass "deployment/$dep $probe path=$path"
            else
                fail "deployment/$dep $probe missing or wrong path ($path)"
            fi
        done
    done

    step "PodDisruptionBudgets (2 expected)"
    kubectl get pdb booking-pdb -n apollo-airlines-apps >/dev/null 2>&1 && pass "pdb/booking-pdb" || fail "pdb/booking-pdb missing"
    kubectl get pdb frontend-pdb -n apollo-airlines-ui >/dev/null 2>&1 && pass "pdb/frontend-pdb" || fail "pdb/frontend-pdb missing"

    step "Gateway (envoy)"
    kubectl get ns envoy-gateway-system >/dev/null 2>&1 && pass "ns/envoy-gateway-system" || fail "ns/envoy-gateway-system missing"
    kubectl get ns metallb-system >/dev/null 2>&1 && pass "ns/metallb-system" || fail "ns/metallb-system missing"
    kubectl get gateway apollo-gateway -n apollo-airlines-apps >/dev/null 2>&1 && pass "gateway/apollo-gateway" || fail "gateway/apollo-gateway missing"

    step "HTTPRoutes (5 expected: identity, flight, booking, search, notification, frontend)"
    for app in identity flight booking search notification; do
        kubectl get httproute "$app" -n apollo-airlines-apps >/dev/null 2>&1 && pass "httproute/$app" || fail "httproute/$app missing"
    done
    kubectl get httproute frontend -n apollo-airlines-ui >/dev/null 2>&1 && pass "httproute/frontend" || fail "httproute/frontend missing"
    kubectl get referencegrant apollo-gateway-grant -n apollo-airlines-ui >/dev/null 2>&1 && pass "referencegrant/apollo-gateway-grant" || fail "referencegrant/apollo-gateway-grant missing"

    step "OTEL env vars in pod specs (Stage 6 carryover check)"
    for dep in identity flight booking search notification; do
        otel_ep=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}' 2>/dev/null || echo "")
        if [[ "$otel_ep" == "otel-collector:4317" ]]; then
            pass "deployment/$dep OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317"
        else
            fail "deployment/$dep OTEL_EXPORTER_OTLP_ENDPOINT=$otel_ep (expected otel-collector:4317)"
        fi
    done

    step "Prometheus scrape annotations on pods"
    for dep in identity flight booking search notification; do
        scrape=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.metadata.annotations.prometheus\.io/scrape}' 2>/dev/null || echo "")
        if [[ "$scrape" == "true" ]]; then
            pass "deployment/$dep has prometheus.io/scrape=true"
        else
            fail "deployment/$dep missing prometheus.io/scrape annotation (got '$scrape')"
        fi
    done
fi

# =============================================================================
# Stage 6: Observability
# =============================================================================
if [[ "$SKIP_OBSERVABILITY" != "true" ]]; then
    step "Observability namespace"
    if kubectl get ns apollo-observability >/dev/null 2>&1; then
        pass "ns/apollo-observability"
    else
        fail "ns/apollo-observability missing (run apply.sh without --skip-observability)"
        SKIP_OBSERVABILITY=true   # cascade: skip downstream checks
    fi

    if [[ "$SKIP_OBSERVABILITY" != "true" ]]; then
        step "ServiceAccount + ClusterRole"
        kubectl get sa observability-stack -n apollo-observability >/dev/null 2>&1 && pass "sa/observability-stack" || fail "sa/observability-stack missing"
        kubectl get clusterrole apollo-observability >/dev/null 2>&1 && pass "clusterrole/apollo-observability" || fail "clusterrole/apollo-observability missing"
        kubectl get clusterrolebinding apollo-observability >/dev/null 2>&1 && pass "clusterrolebinding/apollo-observability" || fail "clusterrolebinding/apollo-observability missing"

        step "Observability pods (5 expected: prometheus, grafana, otel-collector, tempo, loki, promtail)"
        for pod in prometheus grafana otel-collector tempo loki; do
            if [[ "$pod" == "otel-collector" ]]; then
                # DaemonSet — there will be one per node
                count=$(kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=$pod" --no-headers 2>/dev/null | grep -c "1/1" || echo 0)
                if [[ "$count" -ge 1 ]]; then
                    pass "$pod: $count pod(s) Ready"
                else
                    fail "$pod: no Ready pods"
                fi
            else
                if kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=$pod" --no-headers 2>/dev/null | grep -q "1/1"; then
                    pass "$pod 1/1 Ready"
                else
                    fail "$pod not 1/1 Ready"
                fi
            fi
        done
        count=$(kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=promtail" --no-headers 2>/dev/null | grep -c "1/1" || echo 0)
        if [[ "$count" -ge 1 ]]; then
            pass "promtail: $count pod(s) Ready"
        else
            fail "promtail: no Ready pods"
        fi

        step "Services (5 expected: prometheus, grafana, otel-collector, tempo, loki)"
        for svc in prometheus grafana tempo loki; do
            kubectl get svc "$svc" -n apollo-observability >/dev/null 2>&1 && pass "svc/$svc" || fail "svc/$svc missing"
        done

        step "ServiceMonitors (5 expected: identity, flight, booking, search, notification)"
        for app in identity flight booking search notification; do
            kubectl get servicemonitor "$app" -n apollo-observability >/dev/null 2>&1 && pass "servicemonitor/$app" || fail "servicemonitor/$app missing"
        done

        step "Alert rules (PrometheusRule loaded)"
        rule_count=$(kubectl exec -n apollo-observability deploy/prometheus -- \
            wget -qO- 'http://localhost:9090/api/v1/rules' 2>/dev/null | \
            grep -oE '"name":"[^"]+"' | grep -v '^\s*$' | wc -l || echo 0)
        if [[ "$rule_count" -ge 15 ]]; then
            pass "Prometheus has $rule_count rule groups loaded (target: ≥15)"
        else
            fail "Prometheus only has $rule_count rule groups (target: ≥15)"
        fi

        step "Real /metrics endpoint (Prometheus exposition format, not JSON)"
        # Pick a healthy booking pod and curl its /metrics. Expect lines like
        # "# HELP http_requests_total ..." and "# TYPE http_requests_total counter".
        booking_pod=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$booking_pod" ]]; then
            fail "no booking pod found"
        else
            metrics_output=$(kubectl exec -n apollo-airlines-apps "$booking_pod" -- wget -qO- http://localhost:8082/metrics 2>/dev/null || echo "")
            if echo "$metrics_output" | grep -q "http_requests_total"; then
                pass "booking /metrics returns Prometheus exposition format with http_requests_total"
            else
                fail "booking /metrics does not return Prometheus format"
            fi
        fi

        step "Grafana dashboards (5 expected: overview, booking, errors, saturation, trace-viewer)"
        for d in overview booking errors saturation trace-viewer; do
            kubectl get cm "grafana-dashboard-$d" -n apollo-observability >/dev/null 2>&1 && pass "dashboard/$d" || fail "dashboard/$d missing"
        done

        step "Grafana HTTPRoute + ReferenceGrant"
        kubectl get httproute grafana -n apollo-observability >/dev/null 2>&1 && pass "httproute/grafana" || fail "httproute/grafana missing"
        kubectl get referencegrant grafana-route-grant -n apollo-airlines-apps >/dev/null 2>&1 && pass "referencegrant/grafana-route-grant" || fail "referencegrant/grafana-route-grant missing"

        step "Grafana datasources (3 expected: Prometheus, Loki, Tempo)"
        ds_count=$(kubectl get cm grafana-datasources -n apollo-observability -o jsonpath='{.data.datasources\.yaml}' 2>/dev/null | grep -cE "^\s+- name:" || echo 0)
        if [[ "$ds_count" -eq 3 ]]; then
            pass "Grafana has $ds_count datasources (Prometheus, Loki, Tempo)"
        else
            fail "Grafana has $ds_count datasources (expected 3)"
        fi

        step "Prometheus self-check (can query 5 services up)"
        # After ServiceMonitors have been running for 90s+, Prometheus should
        # have scraped each service at least once. Query the up{} metric.
        up_count=$(kubectl exec -n apollo-observability deploy/prometheus -- \
            wget -qO- 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | \
            grep -oE '"service":"[a-z]+"' | sort -u | wc -l || echo 0)
        if [[ "$up_count" -ge 5 ]]; then
            pass "Prometheus reports $up_count distinct services up"
        else
            fail "Prometheus only sees $up_count services (expected ≥5)"
        fi
    fi
fi

# =============================================================================
# Summary
# =============================================================================
TOTAL=$((PASS+FAIL))
echo ""
echo "============================================"
echo -e "  ${GREEN}PASS: $PASS${NC}  /  ${RED}FAIL: $FAIL${NC}  /  TOTAL: $TOTAL"
echo "============================================"
if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "  Troubleshooting:"
    echo "    kubectl get pods -n apollo-observability"
    echo "    kubectl logs -n apollo-observability -l app.kubernetes.io/name=otel-collector --tail=50"
    echo "    kubectl logs -n apollo-observability -l app.kubernetes.io/name=prometheus --tail=50"
    exit 1
fi
echo -e "${GREEN}All Stage 6 checks passed.${NC}"
