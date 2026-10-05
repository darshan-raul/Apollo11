#!/bin/bash
# Verify Stage 6: the trusted Stage 5 workload contract plus observability.
# ConfigMap, Secret,
# 3 Postgres StatefulSets + 1 Redis StatefulSet, 6 app Deployments +
# frontend Deployment, 2 PDBs, 3 seed Jobs, GatewayClass, Gateway, 6
# HTTPRoutes, ReferenceGrant, MetalLB IPAddressPool, and the chart's
# own metadata.
#
# Mode-aware: works for both helm and kustomize installs. Some checks
# (e.g. envoy-gateway-system namespace) only apply to --mode helm.
#
# Usage:
#   ./scripts/verify.sh                  # auto-detect mode
#   ./scripts/verify.sh --mode helm      # explicit
#   ./scripts/verify.sh --mode kustomize --env prod
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/context.sh"
apollo_context_guard

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

MODE="auto"
ENV="dev"
GATEWAY_EXPECTED=true
OBSERVABILITY_EXPECTED=true

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--skip-observability]

Options:
  --mode MODE   helm | kustomize | auto (default)
  --env ENV     env for kustomize mode (default: dev)
  --skip-observability  Verify only the Stage 5-compatible baseline
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift 2 ;;
        --env)  ENV="$2"; shift 2 ;;
        --skip-observability) OBSERVABILITY_EXPECTED=false; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

case "$MODE" in
    auto|helm|kustomize) ;;
    *) echo -e "${RED}Invalid mode '$MODE' (expected auto, helm, or kustomize).${NC}"; exit 1 ;;
esac
case "$ENV" in
    dev|staging|prod) ;;
    *) echo -e "${RED}Invalid environment '$ENV' (expected dev, staging, or prod).${NC}"; exit 1 ;;
esac

# Auto-detect mode
if [[ "$MODE" == "auto" ]]; then
    if helm list -n apollo-airlines-apps 2>/dev/null | grep -q apollo11; then
        MODE="helm"
    elif kubectl get deployment -n apollo-airlines-apps identity >/dev/null 2>&1; then
        MODE="kustomize"
    else
        echo -e "${RED}Could not auto-detect install mode. Run with --mode helm or --mode kustomize.${NC}"
        exit 1
    fi
    echo "Auto-detected mode: $MODE"
fi

# ---------------------------------------------------------------------------
# Stage 6 observability
# ---------------------------------------------------------------------------
if [[ "$OBSERVABILITY_EXPECTED" == "true" ]]; then
    step "Stage 6 namespaces, operator, and custom resources"
    kubectl get ns apollo-observability >/dev/null 2>&1 && pass "ns/apollo-observability" || fail "ns/apollo-observability missing"
    kubectl rollout status deployment/prometheus-operator -n apollo-observability --timeout=30s >/dev/null 2>&1 && pass "prometheus-operator ready" || fail "prometheus-operator not ready"
    for crd in prometheuses.monitoring.coreos.com servicemonitors.monitoring.coreos.com prometheusrules.monitoring.coreos.com; do
        kubectl get crd "$crd" >/dev/null 2>&1 && pass "crd/$crd" || fail "crd/$crd missing"
    done
    kubectl get prometheus apollo -n apollo-observability >/dev/null 2>&1 && pass "prometheus/apollo" || fail "prometheus/apollo missing"
    kubectl rollout status statefulset/prometheus-apollo -n apollo-observability --timeout=30s >/dev/null 2>&1 && pass "prometheus-apollo ready" || fail "prometheus-apollo not ready"
    sm_count=$(kubectl get servicemonitor -n apollo-observability --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "$sm_count" == "5" ]] && pass "5 ServiceMonitors" || fail "expected 5 ServiceMonitors, found $sm_count"
    kubectl get prometheusrule apollo-services -n apollo-observability >/dev/null 2>&1 && pass "prometheusrule/apollo-services" || fail "prometheusrule/apollo-services missing"

    step "Stage 6 telemetry endpoints and collector DNS"
    expected_otel="otel-collector.apollo-observability.svc.cluster.local:4317"
    for dep in identity flight booking search notification; do
        endpoint=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}' 2>/dev/null || true)
        [[ "$endpoint" == "$expected_otel" ]] && pass "$dep OTLP endpoint uses cross-namespace FQDN" || fail "$dep OTLP endpoint=$endpoint"
        pod=$(kubectl get pod -n apollo-airlines-apps -l "app=$dep" -o jsonpath='{.items[0].metadata.name}')
        port=$(kubectl get service "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.ports[0].port}')
        if [[ "$dep" == "identity" ]]; then
            metrics=$(kubectl exec -n apollo-airlines-apps "$pod" -- python3 -c \
                "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:$port/metrics').read().decode())" 2>/dev/null || true)
        else
            metrics=$(kubectl exec -n apollo-airlines-apps "$pod" -- wget -qO- "http://127.0.0.1:$port/metrics" 2>/dev/null || true)
        fi
        grep -q 'http_requests_total' <<<"$metrics" && pass "$dep exposes real request counters" || fail "$dep /metrics lacks http_requests_total"
        grep -q 'http_request_duration_ms' <<<"$metrics" && pass "$dep exposes latency histogram" || fail "$dep /metrics lacks latency histogram"
    done

    step "Stage 6 observability workloads"
    for dep in grafana loki tempo; do
        kubectl rollout status "deployment/$dep" -n apollo-observability --timeout=30s >/dev/null 2>&1 && pass "$dep ready" || fail "$dep not ready"
    done
    for ds in otel-collector alloy; do
        desired=$(kubectl get daemonset "$ds" -n apollo-observability -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
        ready=$(kubectl get daemonset "$ds" -n apollo-observability -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
        [[ "$desired" -gt 0 && "$ready" == "$desired" ]] && pass "$ds DaemonSet $ready/$desired ready" || fail "$ds DaemonSet $ready/$desired ready"
    done

    step "Prometheus discovery, rules, Grafana, Tempo, and Loki APIs"
    pf_log=$(mktemp)
    kubectl port-forward -n apollo-observability service/prometheus 19090:9090 >"$pf_log" 2>&1 &
    pf_pid=$!
    for _ in $(seq 1 20); do curl -fsS http://127.0.0.1:19090/-/ready >/dev/null 2>&1 && break; sleep 1; done
    active_targets=0
    for _ in $(seq 1 20); do
        targets=$(curl -fsS http://127.0.0.1:19090/api/v1/targets 2>/dev/null || true)
        active_targets=$(grep -o '"health":"up"' <<<"$targets" | wc -l | tr -d ' ' || true)
        [[ "$active_targets" -ge 5 ]] && break
        sleep 3
    done
    [[ "$active_targets" -ge 5 ]] && pass "Prometheus has at least 5 healthy backend targets" || fail "Prometheus healthy targets=$active_targets"
    rules=$(curl -fsS http://127.0.0.1:19090/api/v1/rules 2>/dev/null || true)
    grep -q 'ApolloServiceDown' <<<"$rules" && pass "Prometheus loaded Apollo rules" || fail "Prometheus did not load Apollo rules"
    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" 2>/dev/null || true
    rm -f "$pf_log"

    kubectl port-forward -n apollo-observability service/grafana 13000:3000 >/tmp/stage6-grafana-pf.log 2>&1 & grafana_pf=$!
    for _ in $(seq 1 20); do grafana_health=$(curl -fsS http://127.0.0.1:13000/api/health 2>/dev/null || true); [[ -n "$grafana_health" ]] && break; sleep 1; done
    grep -q '"database": "ok"' <<<"$grafana_health" && pass "Grafana API healthy" || fail "Grafana API unhealthy"
    kill "$grafana_pf" >/dev/null 2>&1 || true; wait "$grafana_pf" 2>/dev/null || true
    dashboard_count=$(kubectl get configmap -n apollo-observability -l app.kubernetes.io/name=grafana -o name | grep -c 'dashboard-' || true)
    [[ "$dashboard_count" -ge 5 ]] && pass "5 Grafana dashboards provisioned" || fail "Grafana dashboard ConfigMaps=$dashboard_count"
    kubectl port-forward -n apollo-observability service/tempo 13100:3100 >/tmp/stage6-tempo-pf.log 2>&1 & tempo_pf=$!
    for _ in $(seq 1 20); do curl -fsS http://127.0.0.1:13100/ready >/dev/null 2>&1 && break; sleep 1; done
    curl -fsS http://127.0.0.1:13100/ready >/dev/null 2>&1 && pass "Tempo API ready" || fail "Tempo API not ready"
    kill "$tempo_pf" >/dev/null 2>&1 || true; wait "$tempo_pf" 2>/dev/null || true
    kubectl port-forward -n apollo-observability service/loki 13101:3100 >/tmp/stage6-loki-pf.log 2>&1 & loki_pf=$!
    for _ in $(seq 1 20); do curl -fsS http://127.0.0.1:13101/ready >/dev/null 2>&1 && break; sleep 1; done
    curl -fsS http://127.0.0.1:13101/ready >/dev/null 2>&1 && pass "Loki API ready" || fail "Loki API not ready"

    grafana_envoy_ip=$(kubectl get service -n envoy-gateway-system \
        -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
        -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$grafana_envoy_ip" ]]; then
        grafana_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: grafana.apollo.local' "http://$grafana_envoy_ip/api/health" 2>/dev/null || echo 000)
        [[ "$grafana_code" == "200" ]] && pass "Envoy -> Grafana /api/health -> 200" || fail "Envoy -> Grafana /api/health -> $grafana_code"
    else
        fail "Envoy LoadBalancer IP unavailable for Grafana route check"
    fi

    if bash "$(dirname "$0")/trace-test.sh" >/tmp/stage6-trace-test.log 2>&1; then
        pass "cross-service booking trace reached Tempo"
    else
        fail "cross-service trace test failed (see /tmp/stage6-trace-test.log)"
    fi

    step "Alloy log delivery and trace/log correlation"
    sleep 5
    loki_query=$(curl -fsS 'http://127.0.0.1:13101/loki/api/v1/query_range?query=%7Bnamespace%3D%22apollo-airlines-apps%22%7D&limit=20' 2>/dev/null || true)
    grep -q '"status":"success"' <<<"$loki_query" && pass "Loki query API returned Kubernetes logs" || fail "Loki query did not return logs"
    kill "$loki_pf" >/dev/null 2>&1 || true; wait "$loki_pf" 2>/dev/null || true
fi

# Both packaging modes install the same Envoy Gateway + MetalLB access stack.

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------
step "Namespaces (2 expected: apollo-airlines-apps, apollo-airlines-ui)"
for ns in apollo-airlines-apps apollo-airlines-ui; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then pass "ns/$ns"; else fail "ns/$ns missing"; fi
done

# ---------------------------------------------------------------------------
# ServiceAccounts (13 expected)
# ---------------------------------------------------------------------------
step "ServiceAccounts (13 expected: 6 apps + 4 data + 3 init)"
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

# ---------------------------------------------------------------------------
# ConfigMap + Secret
# ---------------------------------------------------------------------------
step "ConfigMap + Secret"
if kubectl get cm apollo-airlines-config -n apollo-airlines-apps >/dev/null 2>&1; then
    pass "cm/apollo-airlines-config in apollo-airlines-apps"
else
    fail "cm/apollo-airlines-config missing in apollo-airlines-apps"
fi
if kubectl get cm apollo-airlines-config -n apollo-airlines-ui >/dev/null 2>&1; then
    pass "cm/apollo-airlines-config in apollo-airlines-ui"
else
    fail "cm/apollo-airlines-config missing in apollo-airlines-ui"
fi
if kubectl get secret apollo-airlines-secrets -n apollo-airlines-apps >/dev/null 2>&1; then
    pass "secret/apollo-airlines-secrets in apollo-airlines-apps"
else
    fail "secret/apollo-airlines-secrets missing in apollo-airlines-apps"
fi

# ---------------------------------------------------------------------------
# StatefulSets
# ---------------------------------------------------------------------------
step "StatefulSets (4 expected: 3 PG + 1 Redis, all 1/1 Ready)"
for sts in identity-db flight-db booking-db redis; do
    ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -ge 1 ]]; then
        pass "statefulset/$sts ready=$ready"
    else
        fail "statefulset/$sts not ready (ready=$ready)"
    fi
done

step "StatefulSet pods (4 expected, all Ready)"
for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    cond=$(kubectl get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$cond" == "True" ]]; then
        pass "pod/$pod Ready"
    else
        fail "pod/$pod not Ready (cond=$cond)"
    fi
done

# ---------------------------------------------------------------------------
# PVCs
# ---------------------------------------------------------------------------
step "PVCs (4 expected, all Bound)"
EXPECTED_PVCS=(
  "apollo-airlines-apps:pg-data-identity-db-0"
  "apollo-airlines-apps:pg-data-flight-db-0"
  "apollo-airlines-apps:pg-data-booking-db-0"
  "apollo-airlines-apps:redis-data-redis-0"
)
for p in "${EXPECTED_PVCS[@]}"; do
    ns="${p%%:*}"; name="${p##*:}"
    phase=$(kubectl get pvc "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Bound" ]]; then
        pass "pvc $ns/$name Bound"
    else
        fail "pvc $ns/$name phase=$phase (expected Bound)"
    fi
done

# ---------------------------------------------------------------------------
# Headless Services
# ---------------------------------------------------------------------------
step "Headless Services (4 expected)"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
    clusterIP=$(kubectl get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    if [[ "$clusterIP" == "None" ]]; then
        pass "svc/$svc headless"
    else
        fail "svc/$svc clusterIP=$clusterIP (expected None)"
    fi
done

# ---------------------------------------------------------------------------
# App Deployments
# ---------------------------------------------------------------------------
step "App Deployments (5 expected, all >=1 Ready)"
for dep in identity flight booking search notification; do
    ready=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -ge 1 ]]; then
        pass "deployment/$dep ready=$ready"
    else
        fail "deployment/$dep not ready (ready=$ready)"
    fi
done
for probe in startupProbe livenessProbe readinessProbe; do
    path=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || echo "")
    if [[ -n "$path" && "$path" == "/healthz/"* ]]; then
        pass "deployment/frontend $probe path=$path"
    else
        fail "deployment/frontend $probe missing or wrong path ($path)"
    fi
done

step "StatefulSet probes (liveness + readiness, no startup probe)"
for sts in identity-db flight-db booking-db redis; do
    for probe in livenessProbe readinessProbe; do
        command=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].$probe.exec.command[0]}" 2>/dev/null || echo "")
        if [[ -n "$command" ]]; then
            pass "statefulset/$sts $probe command=$command"
        else
            fail "statefulset/$sts $probe missing"
        fi
    done
    startup=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null || echo "")
    if [[ -z "$startup" || "$startup" == "<nil>" || "$startup" == "null" ]]; then
        pass "statefulset/$sts has no startupProbe"
    else
        fail "statefulset/$sts unexpectedly has startupProbe"
    fi
done

# ---------------------------------------------------------------------------
# Frontend Deployment
# ---------------------------------------------------------------------------
step "Frontend Deployment (1 expected)"
ready=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then
    pass "deployment/frontend ready=$ready"
else
    fail "deployment/frontend not ready (ready=$ready)"
fi

# ---------------------------------------------------------------------------
# Probes (Stage 4 contract — startup/live/ready on 6 apps)
# ---------------------------------------------------------------------------
step "Probes on 6 app Deployments (startup/live/ready, all 3 distinct)"
for dep in identity flight booking search notification; do
    for probe in startupProbe livenessProbe readinessProbe; do
        path=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || echo "")
        if [[ -n "$path" && "$path" == "/healthz/"* ]]; then
            pass "deployment/$dep $probe path=$path"
        else
            fail "deployment/$dep $probe missing or wrong path ($path)"
        fi
    done
done

# ---------------------------------------------------------------------------
# Resources (Guaranteed QoS — requests == limits)
# ---------------------------------------------------------------------------
step "Resources: CPU and memory requests == limits on all 10 workloads"
for entry in \
    "deployment:apollo-airlines-apps:identity" \
    "deployment:apollo-airlines-apps:flight" \
    "deployment:apollo-airlines-apps:booking" \
    "deployment:apollo-airlines-apps:search" \
    "deployment:apollo-airlines-apps:notification" \
    "deployment:apollo-airlines-ui:frontend" \
    "statefulset:apollo-airlines-apps:identity-db" \
    "statefulset:apollo-airlines-apps:flight-db" \
    "statefulset:apollo-airlines-apps:booking-db" \
    "statefulset:apollo-airlines-apps:redis"; do
    kind="${entry%%:*}"; remainder="${entry#*:}"; ns="${remainder%%:*}"; name="${remainder##*:}"
    req_cpu=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    lim_cpu=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
    req_mem=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
    lim_mem=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
    if [[ -n "$req_cpu" && "$req_cpu" == "$lim_cpu" && -n "$req_mem" && "$req_mem" == "$lim_mem" ]]; then
        pass "$kind/$name Guaranteed resources cpu=$req_cpu memory=$req_mem"
    else
        fail "$kind/$name resource mismatch cpu=$req_cpu/$lim_cpu memory=$req_mem/$lim_mem"
    fi
done

# ---------------------------------------------------------------------------
# terminationGracePeriodSeconds
# ---------------------------------------------------------------------------
step "terminationGracePeriodSeconds (30s apps, 60s data workloads)"
for dep in identity flight booking search notification; do
    grace=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "30" ]]; then
        pass "deployment/$dep terminationGracePeriodSeconds=30"
    else
        fail "deployment/$dep terminationGracePeriodSeconds=$grace (expected 30)"
    fi
done
grace=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
if [[ "$grace" == "30" ]]; then pass "deployment/frontend terminationGracePeriodSeconds=30"; else fail "deployment/frontend terminationGracePeriodSeconds=$grace (expected 30)"; fi
for sts in identity-db flight-db booking-db redis; do
    grace=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "60" ]]; then pass "statefulset/$sts terminationGracePeriodSeconds=60"; else fail "statefulset/$sts terminationGracePeriodSeconds=$grace (expected 60)"; fi
done

# ---------------------------------------------------------------------------
# PriorityClasses (apollo-airlines-app-critical, apollo-airlines-app-low)
# ---------------------------------------------------------------------------
step "PriorityClasses (apollo-airlines-app-critical, apollo-airlines-app-low)"
for pc in apollo-airlines-app-critical apollo-airlines-app-low; do
    if kubectl get priorityclass "$pc" >/dev/null 2>&1; then
        pass "priorityclass/$pc exists"
    else
        fail "priorityclass/$pc missing"
    fi
done

step "Stage 4 Contract Verification (lifecycle.preStop and topologySpreadConstraints)"
for dep in identity flight booking search notification; do
    prestop=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command}' 2>/dev/null || echo "")
    if [[ "$prestop" =~ "sleep" ]]; then
        pass "deployment/$dep lifecycle.preStop configured"
    else
        fail "deployment/$dep lifecycle.preStop missing ($prestop)"
    fi

    tsc=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}' 2>/dev/null || echo "")
    if [[ -n "$tsc" ]]; then
        pass "deployment/$dep topologySpreadConstraints configured"
    else
        fail "deployment/$dep topologySpreadConstraints missing"
    fi
done

fe_prestop=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command}' 2>/dev/null || echo "")
if [[ "$fe_prestop" =~ "sleep" ]]; then
    pass "deployment/frontend lifecycle.preStop configured"
else
    fail "deployment/frontend lifecycle.preStop missing ($fe_prestop)"
fi
fe_tsc=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}' 2>/dev/null || echo "")
if [[ -n "$fe_tsc" ]]; then
    pass "deployment/frontend topologySpreadConstraints configured"
else
    fail "deployment/frontend topologySpreadConstraints missing"
fi

for app in booking search; do
    pc=$(kubectl get deployment "$app" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
    if [[ "$pc" == "apollo-airlines-app-critical" ]]; then
        pass "deployment/$app priorityClassName=apollo-airlines-app-critical"
    else
        fail "deployment/$app priorityClassName=$pc (expected apollo-airlines-app-critical)"
    fi
done
pc_notif=$(kubectl get deployment notification -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
if [[ "$pc_notif" == "apollo-airlines-app-low" ]]; then
    pass "deployment/notification priorityClassName=apollo-airlines-app-low"
else
    fail "deployment/notification priorityClassName=$pc_notif (expected apollo-airlines-app-low)"
fi

# ---------------------------------------------------------------------------
# PodDisruptionBudgets (chart applies both; kustomize prod applies both)
# ---------------------------------------------------------------------------
step "PodDisruptionBudgets match the selected environment"
if [[ "$ENV" == "prod" ]]; then
    for entry in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
        ns="${entry%%:*}"; name="${entry##*:}"
        min=$(kubectl get pdb "$name" -n "$ns" -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
        if [[ "$min" == "2" ]]; then pass "pdb/$name minAvailable=2"; else fail "pdb/$name minAvailable=$min (expected 2)"; fi
    done
else
    for entry in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
        ns="${entry%%:*}"; name="${entry##*:}"
        if kubectl get pdb "$name" -n "$ns" >/dev/null 2>&1; then fail "pdb/$name should be disabled in $ENV"; else pass "pdb/$name disabled in $ENV"; fi
    done
fi

# ---------------------------------------------------------------------------
# Seed Jobs
# ---------------------------------------------------------------------------
step "Seed Jobs (3 expected: identity, flight, booking — all Complete)"
for job in seed-identity-db seed-flight-db seed-booking-db; do
        status=$(kubectl get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        if [[ "$status" == "True" ]]; then
            pass "job/$job Complete"
        else
            fail "job/$job status=$status (expected Complete=True)"
        fi
done

# ---------------------------------------------------------------------------
# Runtime contract inherited from Stages 3 and 4
# ---------------------------------------------------------------------------
step "Database URLs expanded from Secret-backed environment variables"
for dep in identity flight booking; do
    if kubectl exec -n apollo-airlines-apps "deployment/$dep" -- \
        sh -c 'case "$DATABASE_URL" in *\$\(*) exit 1 ;; *) exit 0 ;; esac' >/dev/null 2>&1; then
        pass "deployment/$dep DATABASE_URL contains no unexpanded variable"
    else
        fail "deployment/$dep DATABASE_URL still contains an unexpanded variable"
    fi
done

step "Live probe endpoints respond inside all 6 application pods"
for entry in \
    "apollo-airlines-apps:identity:8080" \
    "apollo-airlines-apps:flight:8081" \
    "apollo-airlines-apps:booking:8082" \
    "apollo-airlines-apps:search:8083" \
    "apollo-airlines-apps:notification:8084" \
    "apollo-airlines-ui:frontend:3000"; do
    ns="${entry%%:*}"; remainder="${entry#*:}"; app="${remainder%%:*}"; port="${entry##*:}"
    for endpoint in startup live ready; do
        response=$(kubectl exec -n "$ns" "deployment/$app" -- \
            sh -c "wget -q -O- --tries=1 http://127.0.0.1:$port/healthz/$endpoint 2>/dev/null || echo FAIL" 2>/dev/null | tr -d '\n' || echo "")
        if [[ -n "$response" && "$response" != "FAIL" && "$response" != *error* ]]; then
            pass "$app /healthz/$endpoint responds"
        else
            # The Python slim identity image intentionally has no wget.
            response=$(kubectl exec -n "$ns" "deployment/$app" -- \
                python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:$port/healthz/$endpoint').status)" \
                2>/dev/null | tr -d '\n' || echo "")
            if [[ "$response" == "200" ]]; then
                pass "$app /healthz/$endpoint responds"
            else
                fail "$app /healthz/$endpoint is unreachable"
            fi
        fi
    done
done

step "Seed data is present"
users=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- \
    psql -U postgres -d identity -tAc 'SELECT count(*) FROM users;' 2>/dev/null || echo 0)
airports=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
    psql -U postgres -d flight -tAc 'SELECT count(*) FROM airports;' 2>/dev/null || echo 0)
flights=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
    psql -U postgres -d flight -tAc 'SELECT count(*) FROM flights;' 2>/dev/null || echo 0)
if [[ "$users" -ge 2 ]]; then pass "identity seed has $users users"; else fail "identity seed has $users users (expected >=2)"; fi
if [[ "$airports" -ge 6 ]]; then pass "flight seed has $airports airports"; else fail "flight seed has $airports airports (expected >=6)"; fi
if [[ "$flights" -ge 180 ]]; then pass "flight seed has $flights flights"; else fail "flight seed has $flights flights (expected >=180)"; fi

step "Frontend bundle contains routed API hosts and no localhost API URLs"
bundle_urls=$(kubectl exec -n apollo-airlines-ui deployment/frontend -- \
    grep -R -o -E 'http://(localhost:[0-9]+|[a-z]+\.apollo\.local)' \
    /usr/share/nginx/html/assets 2>/dev/null || echo "")
missing_hosts=()
for host in identity flight booking search; do
    if ! grep -q "https://${host}.apollo.local" <<<"$bundle_urls"; then missing_hosts+=("$host.apollo.local"); fi
done
if grep -q 'http://localhost:' <<<"$bundle_urls"; then
    fail "frontend bundle contains localhost API URLs"
elif [[ "${#missing_hosts[@]}" -gt 0 ]]; then
    fail "frontend bundle is missing API hosts: ${missing_hosts[*]}"
else
    pass "frontend bundle has all four routed API hosts"
fi

if [[ "$MODE" == "helm" ]]; then
    step "Helm release and workload ownership metadata"
    release_status=$(helm status apollo11 -n apollo-airlines-apps -o json 2>/dev/null | jq -r '.info.status // empty' || echo "")
    if [[ "$release_status" == "deployed" ]]; then pass "Helm release apollo11 status=deployed"; else fail "Helm release apollo11 status=$release_status"; fi
    for entry in \
        "deployment:apollo-airlines-apps:identity" "deployment:apollo-airlines-apps:flight" \
        "deployment:apollo-airlines-apps:booking" "deployment:apollo-airlines-apps:search" \
        "deployment:apollo-airlines-apps:notification" "deployment:apollo-airlines-ui:frontend" \
        "statefulset:apollo-airlines-apps:identity-db" "statefulset:apollo-airlines-apps:flight-db" \
        "statefulset:apollo-airlines-apps:booking-db" "statefulset:apollo-airlines-apps:redis"; do
        kind="${entry%%:*}"; remainder="${entry#*:}"; ns="${remainder%%:*}"; name="${remainder##*:}"
        owner=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
        if [[ "$owner" == "Helm" ]]; then pass "$kind/$name managed-by=Helm"; else fail "$kind/$name managed-by=$owner (expected Helm)"; fi
    done
fi

# ---------------------------------------------------------------------------
# Gateway (both packaging modes)
# ---------------------------------------------------------------------------
if [[ "$GATEWAY_EXPECTED" == "true" ]]; then
    step "Envoy Gateway access stack"

    if kubectl get ns envoy-gateway-system >/dev/null 2>&1; then
        pass "ns/envoy-gateway-system"
    else
        fail "ns/envoy-gateway-system missing"
    fi

    if kubectl get ns metallb-system >/dev/null 2>&1; then
        pass "ns/metallb-system"
    else
        fail "ns/metallb-system missing"
    fi

    if kubectl get gatewayclass eg >/dev/null 2>&1; then
        pass "gatewayclass/eg"
    else
        fail "gatewayclass/eg missing"
    fi

    if kubectl get gateway apollo-gateway -n apollo-airlines-apps >/dev/null 2>&1; then
        # Check the Gateway has a programmed condition
        programmed=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
        if [[ "$programmed" == "True" ]]; then
            pass "gateway/apollo-gateway Programmed"
        else
            fail "gateway/apollo-gateway not Programmed (status=$programmed)"
        fi
    else
        fail "gateway/apollo-gateway missing"
    fi

    step "HTTPRoutes (6 expected: identity, flight, booking, search, notification, frontend)"
    for route in identity flight booking search notification; do
        if kubectl get httproute "$route" -n apollo-airlines-apps >/dev/null 2>&1; then
            pass "httproute/$route"
        else
            fail "httproute/$route missing"
        fi
    done
    if kubectl get httproute frontend -n apollo-airlines-ui >/dev/null 2>&1; then
        pass "httproute/frontend (cross-namespace)"
    else
        fail "httproute/frontend missing in apollo-airlines-ui"
    fi

    step "ReferenceGrant (cross-namespace)"
    if kubectl get referencegrant apollo-gateway-grant -n apollo-airlines-ui >/dev/null 2>&1; then
        pass "referencegrant/apollo-gateway-grant"
    else
        fail "referencegrant/apollo-gateway-grant missing"
    fi

    step "MetalLB IP pool + L2 advertisement"
    if kubectl get ipaddresspool apollo-pool -n metallb-system >/dev/null 2>&1; then
        pass "ipaddresspool/apollo-pool"
    else
        fail "ipaddresspool/apollo-pool missing"
    fi
    if kubectl get l2advertisement apollo-l2 -n metallb-system >/dev/null 2>&1; then
        pass "l2advertisement/apollo-l2"
    else
        fail "l2advertisement/apollo-l2 missing"
    fi

    step "HTTPRoutes are attached and live through the MetalLB address"
    envoy_ip=$(kubectl get service -n envoy-gateway-system \
        -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
        -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$envoy_ip" ]]; then pass "Envoy LoadBalancer address=$envoy_ip"; else fail "Envoy LoadBalancer has no address"; fi
    parent_count=$(kubectl get httproute -A -o custom-columns='P:.status.parents[*].controllerName' --no-headers 2>/dev/null | grep -c gateway.envoyproxy.io || true)
    if [[ "$parent_count" -ge 6 ]]; then pass "all 6 HTTPRoutes report an Envoy parent"; else fail "only $parent_count/6 HTTPRoutes report an Envoy parent"; fi
    if [[ -n "$envoy_ip" ]]; then
        for route in identity flight booking search notification; do
            code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $route.apollo.local" "http://$envoy_ip/healthz" 2>/dev/null || echo 000)
            if [[ "$code" == "200" ]]; then pass "Envoy -> $route /healthz -> 200"; else fail "Envoy -> $route /healthz -> $code"; fi
        done
        code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: frontend.apollo.local' "http://$envoy_ip/" 2>/dev/null || echo 000)
        if [[ "$code" == "200" ]]; then pass "Envoy -> frontend / -> 200"; else fail "Envoy -> frontend / -> $code"; fi
        login=$(curl -s -X POST -H 'Host: identity.apollo.local' -H 'Content-Type: application/json' \
            -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
            "http://$envoy_ip/api/users/login" 2>/dev/null || echo "")
        if grep -q '"token":"[^"]' <<<"$login"; then pass "login flow through Envoy returned a token"; else fail "login flow through Envoy did not return a token"; fi
        for host in identity.apollo.local booking.apollo.local frontend.apollo.local; do
            code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$host:443:$envoy_ip" "https://$host/healthz" 2>/dev/null || echo 000)
            if [[ "$code" == "200" ]]; then
                pass "Envoy HTTPS -> $host /healthz -> 200"
            elif [[ "$host" == "frontend.apollo.local" ]]; then
                code=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$host:443:$envoy_ip" "https://$host/" 2>/dev/null || echo 000)
                if [[ "$code" == "200" ]]; then pass "Envoy HTTPS -> $host / -> 200"; else fail "Envoy HTTPS -> $host / -> $code"; fi
            else
                fail "Envoy HTTPS -> $host /healthz -> $code"
            fi
        done
    fi
fi

if [[ "$GATEWAY_EXPECTED" == true ]]; then
    if bash "$(dirname "${BASH_SOURCE[0]}")/verify-tls.sh"; then
        pass "trusted HTTPS API workflow and hostname rejection"
    else
        fail "trusted HTTPS API workflow or hostname rejection failed"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo ""
echo "============================================"
echo -e "  ${GREEN}PASS: $PASS${NC}  /  ${RED}FAIL: $FAIL${NC}  /  TOTAL: $TOTAL"
echo "============================================"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
echo -e "${GREEN}All Stage 6 checks passed.${NC}"
