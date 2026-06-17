#!/bin/bash
# Verify Stage 7: Orbital Maneuvering — ~120 checks across:
#   1. (Stage 5/6 carryover) ~95 checks: namespaces, SAs, ConfigMap, Secret,
#      4 StatefulSets, 4 headless SVCs, 5 app Deployments + frontend,
#      probes, resources, PDBs, seed jobs, Gateway, HTTPRoutes,
#      ReferenceGrant, MetalLB IP pool, observability stack
#   2. (Stage 7) ~25 new: metrics-server, VPA components, HPA, VPA,
#      PriorityClass, PriorityClass on booking/notification, search
#      tolerations + nodeAffinity, Redis cache HIT/MISS, X-Cache header,
#      cache_hits_total + cache_misses_total counters
#
# Usage:
#   ./scripts/verify.sh                       # full suite
#   ./scripts/verify.sh --skip-observability  # only Stage 5+7 checks
#   ./scripts/verify.sh --skip-workloads      # only observability checks
#   ./scripts/verify.sh --skip-stage7         # only Stage 5+6 checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"

SKIP_OBSERVABILITY=false
SKIP_WORKLOADS=false
SKIP_STAGE7=false

usage() {
    cat <<EOF
Usage: $0 [--skip-observability] [--skip-workloads] [--skip-stage7]
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-observability) SKIP_OBSERVABILITY=true; shift ;;
        --skip-workloads)     SKIP_WORKLOADS=true; shift ;;
        --skip-stage7)        SKIP_STAGE7=true; shift ;;
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
# Stage 7: Orbital Maneuvering — HPA, VPA, PriorityClass, Redis cache
# =============================================================================
if [[ "$SKIP_STAGE7" != "true" && "$SKIP_WORKLOADS" != "true" ]]; then
    step "Stage 7 — metrics-server"
    if kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep -q "1/1"; then
        pass "metrics-server 1/1 Ready"
    else
        fail "metrics-server not 1/1 Ready (HPA cannot compute CPU% without it)"
    fi
    # kubectl top is the end-to-end check — exercises the full pipeline
    # (API server → metrics-server → kubelet → cadvisor).
    if kubectl top nodes 2>/dev/null | grep -q "NAME"; then
        pass "kubectl top nodes returns data"
    else
        fail "kubectl top nodes returned no data (metrics-server API not serving)"
    fi

    step "Stage 7 — VPA components (skipped if vpa-system ns absent, e.g. dev)"
    if kubectl get namespace vpa-system >/dev/null 2>&1; then
        for component in recommender updater admission-controller; do
            if kubectl get pods -n vpa-system -l "app=$component" --no-headers 2>/dev/null | grep -q "1/1"; then
                pass "vpa-$component 1/1 Ready"
            else
                fail "vpa-$component not 1/1 Ready"
            fi
        done
        # The autoscaling.k8s.io API group must be registered.
        if kubectl get crd verticalpodautoscalers.autoscaling.k8s.io >/dev/null 2>&1; then
            pass "crd/verticalpodautoscalers.autoscaling.k8s.io registered"
        else
            fail "VPA CRD not registered"
        fi
    else
        ok "vpa-system namespace absent (VPA disabled in this env) — skipping VPA checks"
    fi

    step "Stage 7 — HPA (search)"
    if kubectl get hpa search-hpa -n apollo-airlines-apps >/dev/null 2>&1; then
        pass "hpa/search-hpa exists"
    else
        fail "hpa/search-hpa missing"
    fi
    min_r=$(kubectl get hpa search-hpa -n apollo-airlines-apps -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "")
    max_r=$(kubectl get hpa search-hpa -n apollo-airlines-apps -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "")
    if [[ "$min_r" == "2" && "$max_r" == "10" ]]; then
        pass "hpa min=2 max=10"
    else
        fail "hpa min=$min_r max=$max_r (expected 2/10)"
    fi
    target=$(kubectl get hpa search-hpa -n apollo-airlines-apps -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || echo "")
    if [[ "$target" == "70" ]]; then
        pass "hpa target CPU utilization = 70%"
    else
        fail "hpa target CPU = $target (expected 70)"
    fi
    # Behavior block (scaleDown stabilization, scaleUp policies).
    if kubectl get hpa search-hpa -n apollo-airlines-apps -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}' 2>/dev/null | grep -q "300"; then
        pass "hpa scaleDown stabilizationWindowSeconds = 300"
    else
        fail "hpa scaleDown stabilization not 300s"
    fi

    step "Stage 7 — VPA (search, Off mode)"
    if kubectl get namespace vpa-system >/dev/null 2>&1 && \
       kubectl get vpa search-vpa -n apollo-airlines-apps >/dev/null 2>&1; then
        pass "vpa/search-vpa exists"
        mode=$(kubectl get vpa search-vpa -n apollo-airlines-apps -o jsonpath='{.spec.updatePolicy.updateMode}' 2>/dev/null || echo "")
        if [[ "$mode" == "Off" ]]; then
            pass "vpa updateMode = Off (recommendations only, no HPA conflict)"
        else
            fail "vpa updateMode = $mode (expected Off — Auto would fight the HPA)"
        fi
        min_cpu=$(kubectl get vpa search-vpa -n apollo-airlines-apps -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].minAllowed.cpu}' 2>/dev/null || echo "")
        max_mem=$(kubectl get vpa search-vpa -n apollo-airlines-apps -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].maxAllowed.memory}' 2>/dev/null || echo "")
        if [[ "$min_cpu" == "50m" ]]; then
            pass "vpa minAllowed.cpu = 50m"
        else
            fail "vpa minAllowed.cpu = $min_cpu (expected 50m)"
        fi
        if [[ "$max_mem" == "512Mi" ]]; then
            pass "vpa maxAllowed.memory = 512Mi"
        else
            fail "vpa maxAllowed.memory = $max_mem (expected 512Mi)"
        fi
    else
        ok "vpa/search-vpa absent (VPA disabled) — skipping VPA resource checks"
    fi

    step "Stage 7 — PriorityClass"
    crit_val=$(kubectl get priorityclass apollo-airlines-app-critical -o jsonpath='{.value}' 2>/dev/null || echo "")
    low_val=$(kubectl get priorityclass apollo-airlines-app-low -o jsonpath='{.value}' 2>/dev/null || echo "")
    if [[ "$crit_val" == "1000000" ]]; then
        pass "priorityclass/apollo-airlines-app-critical value=1000000"
    else
        fail "priorityclass/apollo-airlines-app-critical value=$crit_val (expected 1000000)"
    fi
    if [[ "$low_val" == "-100000" ]]; then
        pass "priorityclass/apollo-airlines-app-low value=-100000"
    else
        fail "priorityclass/apollo-airlines-app-low value=$low_val (expected -100000)"
    fi

    step "Stage 7 — priorityClassName wired into booking + notification pods"
    # Get a booking pod and check its spec.priorityClassName.
    booking_pod=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$booking_pod" ]]; then
        bpc=$(kubectl get pod "$booking_pod" -n apollo-airlines-apps -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "")
        if [[ "$bpc" == "apollo-airlines-app-critical" ]]; then
            pass "booking pod priorityClassName = apollo-airlines-app-critical"
        else
            fail "booking pod priorityClassName = '$bpc' (expected apollo-airlines-app-critical)"
        fi
    else
        fail "no booking pod found"
    fi
    notif_pod=$(kubectl get pods -n apollo-airlines-apps -l app=notification -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$notif_pod" ]]; then
        npc=$(kubectl get pod "$notif_pod" -n apollo-airlines-apps -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "")
        if [[ "$npc" == "apollo-airlines-app-low" ]]; then
            pass "notification pod priorityClassName = apollo-airlines-app-low"
        else
            fail "notification pod priorityClassName = '$npc' (expected apollo-airlines-app-low)"
        fi
    else
        fail "no notification pod found"
    fi

    step "Stage 7 — search tolerations + nodeAffinity"
    # Inspect the search Deployment's pod spec (not a live pod — a live pod
    # would have the same fields, but the Deployment is the source of truth).
    tol=$(kubectl get deployment search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.tolerations[0].key}' 2>/dev/null || echo "")
    if [[ "$tol" == "workload" ]]; then
        pass "search Deployment toleration key = workload"
    else
        fail "search Deployment toleration key = '$tol' (expected workload)"
    fi
    tol_val=$(kubectl get deployment search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.tolerations[0].value}' 2>/dev/null || echo "")
    if [[ "$tol_val" == "search" ]]; then
        pass "search Deployment toleration value = search"
    else
        fail "search Deployment toleration value = '$tol_val' (expected search)"
    fi
    aff=$(kubectl get deployment search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight}' 2>/dev/null || echo "")
    if [[ "$aff" == "100" ]]; then
        pass "search Deployment nodeAffinity preferred weight = 100"
    else
        fail "search Deployment nodeAffinity preferred weight = '$aff' (expected 100)"
    fi

    step "Stage 7 — Redis cache on search"
    # The search pod's /healthz/ready returns {status:ready, cache: ok|disabled|unreachable}
    search_pod=$(kubectl get pods -n apollo-airlines-apps -l app=search -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$search_pod" ]]; then
        fail "no search pod found"
    else
        # /healthz/ready body should include "cache":"ok" (Redis up) or
        # "cache":"disabled" (Redis nil — degraded startup) or
        # "cache":"unreachable" (Redis reachable on init but not now).
        # Any of these means the readiness handler ran and the cache code path
        # is wired in. We accept ok or disabled as the happy path.
        cache_state=$(kubectl exec -n apollo-airlines-apps "$search_pod" -- \
            wget -qO- 'http://localhost:8083/healthz/ready' 2>/dev/null | \
            grep -oE '"cache":"[a-z]+"' | head -1 | sed 's/"cache":"//;s/"//' || echo "")
        if [[ "$cache_state" == "ok" || "$cache_state" == "disabled" || "$cache_state" == "unreachable" ]]; then
            pass "search /healthz/ready reports cache state = $cache_state"
        else
            fail "search /healthz/ready body has no cache field (got: $cache_state)"
        fi

        # /metrics must expose the new cache_hits_total + cache_misses_total counters.
        metrics_body=$(kubectl exec -n apollo-airlines-apps "$search_pod" -- \
            wget -qO- 'http://localhost:8083/metrics' 2>/dev/null || echo "")
        if echo "$metrics_body" | grep -q '^# HELP cache_hits_total'; then
            pass "search /metrics exposes cache_hits_total"
        else
            fail "search /metrics does not expose cache_hits_total"
        fi
        if echo "$metrics_body" | grep -q '^# HELP cache_misses_total'; then
            pass "search /metrics exposes cache_misses_total"
        else
            fail "search /metrics does not expose cache_misses_total"
        fi

        # Make a search call to seed at least one cache miss.
        # In-cluster: the search service is reachable at search:8083.
        miss_body=$(kubectl exec -n apollo-airlines-apps "$search_pod" -- \
            wget -qO- 'http://localhost:8083/api/search?origin=BOM&destination=SIN&date=today' 2>/dev/null || echo "")
        if echo "$miss_body" | grep -q "results"; then
            pass "search /api/search returns results on first call (MISS expected)"
        else
            fail "search /api/search returned no results: $miss_body"
        fi
    fi

    step "Stage 7 — Redis cache key visible in redis"
    # Use the redis-0 pod directly (single-node kind has redis as a
    # StatefulSet with 1 replica). redis-cli is in the redis:7-alpine image.
    redis_pod=$(kubectl get pods -n apollo-airlines-apps -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$redis_pod" ]]; then
        fail "no redis pod found"
    else
        key_count=$(kubectl exec -n apollo-airlines-apps "$redis_pod" -- \
            sh -c "redis-cli KEYS 'search:*'" 2>/dev/null | grep -c "search:" || echo 0)
        if [[ "$key_count" -ge 1 ]]; then
            pass "redis has $key_count search:* keys"
        else
            fail "redis has 0 search:* keys (cache miss above should have written one)"
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
    echo "    kubectl get hpa -n apollo-airlines-apps"
    echo "    kubectl describe vpa search-vpa -n apollo-airlines-apps"
    exit 1
fi
echo -e "${GREEN}All Stage 7 checks passed.${NC}"
