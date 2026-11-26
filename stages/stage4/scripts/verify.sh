#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER=""
CONTEXT="${KUBE_CONTEXT:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [--context kind-apollo11|kind-apollo11-dev] [--cluster NAME]"
            exit 0
            ;;
        --context)
            [[ $# -ge 2 ]] || { echo "--context requires a value" >&2; exit 2; }
            CONTEXT="$2"; shift 2
            ;;
        --cluster)
            [[ $# -ge 2 ]] || { echo "--cluster requires a value" >&2; exit 2; }
            CLUSTER="$2"; shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

CONTEXT="${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
CLUSTER="${CLUSTER:-apollo11}"
ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev")

ctx_matched=false
for allowed in "${ALLOWED_CONTEXTS[@]}"; do
    if [[ "$CONTEXT" == "$allowed" ]]; then
        ctx_matched=true
        break
    fi
done

if [[ "$ctx_matched" != "true" ]]; then
    echo "Refusing to run against context '${CONTEXT:-<none>}'." >&2
    echo "This script only targets one of: ${ALLOWED_CONTEXTS[*]}" >&2
    exit 2
fi

kube() {
    kubectl --context "$CONTEXT" "$@"
}

TARGET_NODE=""
SIGTERM_LOG=""
LOG_PID=""
ROLL_LOAD_PID=""
ROLL_LOAD_LOG=""
ROLL_STOP_FILE=""
BOOKING_ID=""
TOKEN=""
GATEWAY_IP=""

restore_stage4_lab() {
    if [[ -n "$LOG_PID" ]]; then
        kill "$LOG_PID" 2>/dev/null || true
        wait "$LOG_PID" 2>/dev/null || true
    fi
    if [[ -n "$ROLL_LOAD_PID" ]]; then
        [[ -n "$ROLL_STOP_FILE" ]] && touch "$ROLL_STOP_FILE" 2>/dev/null || true
        kill "$ROLL_LOAD_PID" 2>/dev/null || true
        wait "$ROLL_LOAD_PID" 2>/dev/null || true
    fi
    [[ -n "$SIGTERM_LOG" ]] && rm -f "$SIGTERM_LOG"
    [[ -n "$ROLL_LOAD_LOG" ]] && rm -f "$ROLL_LOAD_LOG"
    [[ -n "$ROLL_STOP_FILE" ]] && rm -f "$ROLL_STOP_FILE"
    kube delete pod stage4-taint-probe stage4-probe-lab stage4-oom-probe stage4-cpu-probe -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kube delete service stage4-probe-lab -n apollo-airlines-apps --ignore-not-found >/dev/null 2>&1 || true
    if [[ -n "$TARGET_NODE" ]]; then
        kube taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule- >/dev/null 2>&1 || true
    fi
    if [[ -n "$BOOKING_ID" && -n "$TOKEN" && -n "$GATEWAY_IP" ]]; then
        curl -sS --max-time 10 -X DELETE -H "Host: booking.apollo.local" \
            -H "Authorization: Bearer $TOKEN" \
            "http://${GATEWAY_IP}/api/bookings/${BOOKING_ID}" >/dev/null 2>&1 || true
    fi
}
trap restore_stage4_lab EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

info() {
    echo -e "  ${CYAN}[INFO]${NC} $1"
}

header() {
    echo ""
    echo "=== $1 ==="
}

header "1. Core Namespaces"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
    if kube get namespace "$ns" >/dev/null 2>&1; then
        pass "Namespace $ns exists"
    else
        fail "Namespace $ns is missing"
    fi
done

header "2. ServiceAccount Token Automount Security"
EXPECTED_SAS=(
    "apollo-airlines-apps:identity-db"
    "apollo-airlines-apps:flight-db"
    "apollo-airlines-apps:booking-db"
    "apollo-airlines-apps:redis"
    "apollo-airlines-apps:identity"
    "apollo-airlines-apps:flight"
    "apollo-airlines-apps:booking"
    "apollo-airlines-apps:search"
    "apollo-airlines-apps:notification"
    "apollo-airlines-apps:init-identity-db"
    "apollo-airlines-apps:init-flight-db"
    "apollo-airlines-apps:init-booking-db"
    "apollo-airlines-ui:frontend"
)
for sa_entry in "${EXPECTED_SAS[@]}"; do
    ns="${sa_entry%%:*}"
    sa="${sa_entry##*:}"
    automount=$(kube get serviceaccount "$sa" -n "$ns" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "")
    if [[ "$automount" == "false" ]]; then
        pass "SA $ns/$sa exists (automount=false)"
    else
        fail "SA $ns/$sa missing or automountServiceAccountToken != false"
    fi
done

header "3. StatefulSets & Workload Identity"
for sts in identity-db flight-db booking-db redis; do
    ready=$(kube get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    ready="${ready:-0}"
    if [[ "$ready" -ge 1 ]]; then
        pass "StatefulSet apollo-airlines-apps/$sts ready (replicas=$ready)"
    else
        fail "StatefulSet apollo-airlines-apps/$sts not ready (replicas=$ready)"
    fi
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    status=$(kube get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$status" == "True" ]]; then
        pass "StatefulSet Pod apollo-airlines-apps/$pod is Ready"
    else
        fail "StatefulSet Pod apollo-airlines-apps/$pod is not Ready"
    fi
done

header "4. Persistent Storage (PVCs & PVs)"
EXPECTED_PVCS=(
    "pg-data-identity-db-0"
    "pg-data-flight-db-0"
    "pg-data-booking-db-0"
    "redis-data-redis-0"
)
for pvc in "${EXPECTED_PVCS[@]}"; do
    phase=$(kube get pvc "$pvc" -n apollo-airlines-apps -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Bound" ]]; then
        pass "PVC $pvc is Bound (1Gi)"
    else
        fail "PVC $pvc phase is '$phase' (expected Bound)"
    fi
done

header "5. Headless Services & CoreDNS Resolution"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
    cip=$(kube get service "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    if [[ "$cip" == "None" ]]; then
        pass "Headless Service $svc has clusterIP=None"
    else
        fail "Headless Service $svc clusterIP is '$cip' (expected None)"
    fi
done

header "6. Application Deployments & Seed Jobs"
for dep in identity flight booking search notification; do
    ready=$(kube get pods -n apollo-airlines-apps -l "app=$dep" -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && $2=="True"{c++} END{print c+0}')
    if [[ "$ready" -ge 2 ]]; then
        pass "Deployment apollo-airlines-apps/$dep ready ($ready non-terminating replicas)"
    else
        fail "Deployment apollo-airlines-apps/$dep not ready ($ready non-terminating replicas)"
    fi
done
fe_ready=$(kube get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && $2=="True"{c++} END{print c+0}')
if [[ "$fe_ready" -ge 2 ]]; then
    pass "Deployment apollo-airlines-ui/frontend ready ($fe_ready non-terminating replicas)"
else
    fail "Deployment apollo-airlines-ui/frontend not ready ($fe_ready non-terminating replicas)"
fi

for job in seed-identity-db seed-flight-db seed-booking-db; do
    succ=$(kube get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    succ="${succ:-0}"
    if [[ "$succ" -ge 1 ]]; then
        pass "Database seed job apollo-airlines-apps/$job completed"
    else
        fail "Database seed job apollo-airlines-apps/$job not completed"
    fi
done

header "7. Database Seed Integrity"
user_cnt=$(kube exec -n apollo-airlines-apps identity-db-0 -- psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo "0")
user_cnt="${user_cnt:-0}"
if [[ "$user_cnt" -ge 2 ]]; then
    pass "identity-db users table has $user_cnt rows"
else
    fail "identity-db users table has $user_cnt rows (expected >= 2)"
fi

airport_cnt=$(kube exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo "0")
airport_cnt="${airport_cnt:-0}"
if [[ "$airport_cnt" -ge 6 ]]; then
    pass "flight-db airports table has $airport_cnt rows"
else
    fail "flight-db airports table has $airport_cnt rows (expected >= 6)"
fi

flight_cnt=$(kube exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo "0")
flight_cnt="${flight_cnt:-0}"
if [[ "$flight_cnt" -ge 180 ]]; then
    pass "flight-db flights table has $flight_cnt rows"
else
    fail "flight-db flights table has $flight_cnt rows (expected >= 180)"
fi

header "8. Envoy Gateway & MetalLB Access Stack"
gw_status=$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$gw_status" == "True" ]]; then
    pass "Gateway apollo-gateway is Programmed"
else
    fail "Gateway apollo-gateway is not Programmed (status=$gw_status)"
fi

GATEWAY_IP=$(kube get service -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$GATEWAY_IP" ]]; then
    pass "MetalLB assigned LoadBalancer IP: $GATEWAY_IP"
    for host in identity.apollo.local flight.apollo.local booking.apollo.local search.apollo.local; do
        code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -H "Host: $host" "http://${GATEWAY_IP}/healthz" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
            pass "Envoy Gateway HTTPRoute to $host returned HTTP 200"
        else
            fail "Envoy Gateway HTTPRoute to $host returned HTTP $code"
        fi
    done
    fe_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://${GATEWAY_IP}/" 2>/dev/null || echo "000")
    if [[ "$fe_code" == "200" ]]; then
        pass "Envoy Gateway frontend HTTPRoute returned HTTP 200"
    else
        fail "Envoy Gateway frontend HTTPRoute returned HTTP $fe_code"
    fi
else
    fail "MetalLB did not assign an IP to Envoy Gateway service"
fi

header "9. Stage 4: Probes Configuration (Startup, Liveness, Readiness)"
for dep in identity flight booking search notification; do
    for probe in startupProbe livenessProbe readinessProbe; do
        path=$(kube get deploy "$dep" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
        if [[ -n "$path" ]]; then
            pass "deploy/$dep has $probe ($path)"
        else
            fail "deploy/$dep missing $probe"
        fi
    done
done

for probe in startupProbe livenessProbe readinessProbe; do
    path=$(kube get deploy frontend -n apollo-airlines-ui -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
    if [[ -n "$path" ]]; then
        pass "deploy/frontend has $probe ($path)"
    else
        fail "deploy/frontend missing $probe"
    fi
done

for sts in identity-db flight-db booking-db redis; do
    for probe in livenessProbe readinessProbe; do
        cmd=$(kube get statefulset "$sts" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].${probe}.exec.command[0]}" 2>/dev/null || echo "")
        if [[ -n "$cmd" ]]; then
            pass "statefulset/$sts has $probe ($cmd)"
        else
            fail "statefulset/$sts missing $probe"
        fi
    done
    sp=$(kube get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null || echo "")
    if [[ -z "$sp" || "$sp" == "<nil>" || "$sp" == "null" ]]; then
        pass "statefulset/$sts has no startupProbe (implicit via initdb/redis init)"
    else
        fail "statefulset/$sts should not have startupProbe"
    fi
done

header "10. Stage 4: Live Probe Endpoints Execution"
for app_info in "apollo-airlines-apps:identity:8080" \
                "apollo-airlines-apps:flight:8081" \
                "apollo-airlines-apps:booking:8082" \
                "apollo-airlines-apps:search:8083" \
                "apollo-airlines-apps:notification:8084" \
                "apollo-airlines-ui:frontend:3000"; do
    ns="${app_info%%:*}"
    remainder="${app_info#*:}"
    svc="${remainder%%:*}"
    port="${remainder##*:}"
    for p in startup live ready; do
        resp=$(kube exec -n "$ns" "deploy/$svc" -- sh -c "wget -q -O- http://127.0.0.1:$port/healthz/$p 2>/dev/null || python3 -c \"import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:$port/healthz/$p').read().decode())\" 2>/dev/null || echo FAIL" 2>/dev/null | tr -d '\n' || echo "FAIL")
        if [[ "$resp" != "FAIL" && -n "$resp" ]]; then
            pass "Pod $svc live probe /healthz/$p responded: $(echo "$resp" | head -c 25)"
        else
            fail "Pod $svc live probe /healthz/$p failed"
        fi
    done
done

header "11. Stage 4: Guaranteed QoS & Lifecycle PreStop Hooks"
for dep in identity flight booking search notification; do
    qos=$(kube get pods -n apollo-airlines-apps -l app="$dep" -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "Pod $dep QoS class is Guaranteed (requests == limits)"
    else
        fail "Pod $dep QoS class is '$qos' (expected Guaranteed)"
    fi
    grace=$(kube get deploy "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "30" ]]; then
        pass "deploy/$dep terminationGracePeriodSeconds is 30"
    else
        fail "deploy/$dep terminationGracePeriodSeconds is '$grace' (expected 30)"
    fi
    prestop=$(kube get deploy "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command[0]}' 2>/dev/null || echo "")
    if [[ -n "$prestop" ]]; then
        pass "deploy/$dep has lifecycle preStop hook configured"
    else
        fail "deploy/$dep missing lifecycle preStop hook"
    fi
done

fe_qos=$(kube get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
if [[ "$fe_qos" == "Guaranteed" ]]; then
    pass "Pod frontend QoS class is Guaranteed"
else
    fail "Pod frontend QoS class is '$fe_qos' (expected Guaranteed)"
fi
fe_grace=$(kube get deploy frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
if [[ "$fe_grace" == "30" ]]; then
    pass "deploy/frontend terminationGracePeriodSeconds is 30"
else
    fail "deploy/frontend terminationGracePeriodSeconds is '$fe_grace' (expected 30)"
fi
fe_prestop=$(kube get deploy frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command[0]}' 2>/dev/null || echo "")
if [[ -n "$fe_prestop" ]]; then
    pass "deploy/frontend has lifecycle preStop hook configured"
else
    fail "deploy/frontend missing lifecycle preStop hook"
fi

for sts in identity-db flight-db booking-db redis; do
    qos=$(kube get pod "$sts-0" -n apollo-airlines-apps -o jsonpath='{.status.qosClass}' 2>/dev/null || echo "")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "StatefulSet pod $sts-0 QoS class is Guaranteed"
    else
        fail "StatefulSet pod $sts-0 QoS class is '$qos' (expected Guaranteed)"
    fi
    grace=$(kube get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "60" ]]; then
        pass "statefulset/$sts terminationGracePeriodSeconds is 60"
    else
        fail "statefulset/$sts terminationGracePeriodSeconds is '$grace' (expected 60)"
    fi
done

header "12. Stage 4: PriorityClasses & Scheduling Placement"
for pc in apollo-airlines-app-critical apollo-airlines-app-low; do
    if kube get priorityclass "$pc" >/dev/null 2>&1; then
        val=$(kube get priorityclass "$pc" -o jsonpath='{.value}' 2>/dev/null || echo "")
        pass "PriorityClass $pc exists (value=$val)"
    else
        fail "PriorityClass $pc missing"
    fi
done

for crit_app in booking search; do
    app_pc=$(kube get deploy "$crit_app" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
    if [[ "$app_pc" == "apollo-airlines-app-critical" ]]; then
        pass "deploy/$crit_app assigned priorityClassName=apollo-airlines-app-critical"
    else
        fail "deploy/$crit_app priorityClassName is '$app_pc' (expected apollo-airlines-app-critical)"
    fi
done

notif_pc=$(kube get deploy notification -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
if [[ "$notif_pc" == "apollo-airlines-app-low" ]]; then
    pass "deploy/notification assigned priorityClassName=apollo-airlines-app-low"
else
    fail "deploy/notification priorityClassName is '$notif_pc' (expected apollo-airlines-app-low)"
fi

for dep_entry in "apollo-airlines-apps:booking" "apollo-airlines-apps:flight" "apollo-airlines-apps:search" "apollo-airlines-ui:frontend"; do
    ns="${dep_entry%%:*}"
    dep="${dep_entry##*:}"
    key=$(kube get deploy "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}' 2>/dev/null || echo "")
    if [[ "$key" == "kubernetes.io/hostname" ]]; then
        pass "deploy/$dep has topologySpreadConstraints (topologyKey=kubernetes.io/hostname)"
    else
        fail "deploy/$dep missing topologySpreadConstraints"
    fi
done

search_tol_key=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.tolerations[0].key}' 2>/dev/null || echo "")
search_tol_val=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.tolerations[0].value}' 2>/dev/null || echo "")
search_tol_eff=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.tolerations[0].effect}' 2>/dev/null || echo "")
if [[ "$search_tol_key" == "workload" && "$search_tol_val" == "search" && "$search_tol_eff" == "NoSchedule" ]]; then
    pass "deploy/search has toleration workload=search:NoSchedule"
else
    fail "deploy/search missing expected toleration (got key=$search_tol_key value=$search_tol_val effect=$search_tol_eff)"
fi

search_aff_key=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].key}' 2>/dev/null || echo "")
if [[ "$search_aff_key" == "apollo11.io/search-pool" ]]; then
    pass "deploy/search has preferred nodeAffinity for apollo11.io/search-pool"
else
    fail "deploy/search missing nodeAffinity for apollo11.io/search-pool (got '$search_aff_key')"
fi

search_tsc_taint_pol=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].nodeTaintsPolicy}' 2>/dev/null || echo "")
search_tsc_unsat=$(kube get deploy search -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].whenUnsatisfiable}' 2>/dev/null || echo "")
if [[ "$search_tsc_taint_pol" == "Honor" && "$search_tsc_unsat" == "DoNotSchedule" ]]; then
    pass "deploy/search topologySpreadConstraints sets whenUnsatisfiable=DoNotSchedule and nodeTaintsPolicy=Honor"
else
    fail "deploy/search topologySpreadConstraints unexpected (whenUnsatisfiable=$search_tsc_unsat, nodeTaintsPolicy=$search_tsc_taint_pol)"
fi

header "12b. Stage 4: LimitRanges & ResourceQuotas"
for lr_entry in "apollo-airlines-apps:apollo-airlines-limits" "apollo-airlines-ui:apollo-ui-limits"; do
    ns="${lr_entry%%:*}"
    lr="${lr_entry##*:}"
    def_cpu=$(kube get limitrange "$lr" -n "$ns" -o jsonpath='{.spec.limits[0].default.cpu}' 2>/dev/null || echo "")
    min_mem=$(kube get limitrange "$lr" -n "$ns" -o jsonpath='{.spec.limits[0].min.memory}' 2>/dev/null || echo "")
    if [[ -n "$def_cpu" && -n "$min_mem" ]]; then
        pass "LimitRange $ns/$lr active (default.cpu=$def_cpu, min.memory=$min_mem)"
    else
        fail "LimitRange $ns/$lr missing or incomplete"
    fi
done

for rq_entry in "apollo-airlines-apps:apollo-airlines-quota:30" "apollo-airlines-ui:apollo-ui-quota:10"; do
    ns="${rq_entry%%:*}"
    rem="${rq_entry#*:}"
    rq="${rem%%:*}"
    expected_pods="${rem##*:}"
    hard_pods=$(kube get resourcequota "$rq" -n "$ns" -o jsonpath='{.spec.hard.pods}' 2>/dev/null || echo "")
    used_pods=$(kube get resourcequota "$rq" -n "$ns" -o jsonpath='{.status.used.pods}' 2>/dev/null || echo "")
    if [[ "$hard_pods" == "$expected_pods" && -n "$used_pods" ]]; then
        pass "ResourceQuota $ns/$rq active (pods used=${used_pods}/${hard_pods})"
    else
        fail "ResourceQuota $ns/$rq missing or unexpected (hard.pods=$hard_pods, used.pods=$used_pods)"
    fi
done

header "13. Stage 4: PodDisruptionBudgets (PDB)"
for pdb_entry in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
    ns="${pdb_entry%%:*}"
    pdb="${pdb_entry##*:}"
    min_avail=$(kube get pdb "$pdb" -n "$ns" -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
    healthy=$(kube get pdb "$pdb" -n "$ns" -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "0")
    healthy="${healthy:-0}"
    if [[ "$min_avail" == "1" && "$healthy" -ge 1 ]]; then
        pass "PDB $ns/$pdb active (minAvailable=1, currentHealthy=$healthy)"
    else
        fail "PDB $ns/$pdb not satisfied (minAvailable=$min_avail, healthy=$healthy)"
    fi
done

header "14. Flagship Booking Workflow & Graceful SIGTERM Shutdown Proof"
LOGIN_RESP=$(curl -s --max-time 15 -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
    -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' \
    "http://${GATEWAY_IP}/api/users/login" 2>/dev/null || echo "")
TOKEN=$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("token",""))
except Exception: print("")' <<< "$LOGIN_RESP")
if [[ -n "$TOKEN" ]]; then
    pass "Passenger login succeeded and returned JWT"
else
    fail "Passenger login failed: $LOGIN_RESP"
fi

FLIGHT_RESP=$(curl -s --max-time 15 -H "Host: flight.apollo.local" "http://${GATEWAY_IP}/api/flights" 2>/dev/null || echo "")
FLIGHT_ID=$(python3 -c 'import json,sys
try:
    flights = json.load(sys.stdin).get("flights", [])
    print(next((f["id"] for f in flights if f.get("status") == "SCHEDULED" and f.get("availableSeats", 0) > 0), ""))
except Exception:
    print("")' <<< "$FLIGHT_RESP")
if [[ -n "$FLIGHT_ID" ]]; then
    pass "Flight inventory query returned valid SCHEDULED flight ID: $FLIGHT_ID"
else
    fail "Flight inventory query failed: $FLIGHT_RESP"
fi

if [[ -n "$TOKEN" && -n "$FLIGHT_ID" && -n "$GATEWAY_IP" ]]; then
    BOOKING_RESP=$(curl -s --max-time 15 -X POST -H "Host: booking.apollo.local" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "{\"flightId\":\"$FLIGHT_ID\"}" \
        "http://${GATEWAY_IP}/api/bookings" 2>/dev/null || echo "")
    BOOKING_ID=$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' <<< "$BOOKING_RESP")
else
    BOOKING_RESP=""
    BOOKING_ID=""
fi
if [[ -n "$BOOKING_ID" ]]; then
    pass "Flagship booking workflow succeeded (bookingId: $BOOKING_ID)"
else
    fail "Flagship booking workflow failed: $BOOKING_RESP"
fi

info "Executing reversible termination experiment: Testing graceful SIGTERM shutdown..."
BOOKING_POD=$(kube get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$BOOKING_POD" ]]; then
    SIGTERM_LOG=$(mktemp)
    kube logs -n apollo-airlines-apps "$BOOKING_POD" --follow > "$SIGTERM_LOG" 2>&1 &
    LOG_PID=$!
    sleep 0.5
    kube delete pod "$BOOKING_POD" -n apollo-airlines-apps --wait=false >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    LOG_PID=""
    if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
        pass "Booking pod logged graceful SIGTERM drain before container exit"
    else
        fail "Booking pod did not log graceful SIGTERM shutdown"
    fi
    rm -f "$SIGTERM_LOG"
    SIGTERM_LOG=""

    # Wait on the Deployment, not the label: the label also matches the old
    # Pod while it terminates, and under `set -e` a timed-out wait would end
    # the verifier without a summary.
    if kube rollout status deployment/booking -n apollo-airlines-apps --timeout=120s >/dev/null 2>&1; then
        pass "Booking replacement pod is Ready after termination"
    else
        fail "Booking did not return to full readiness within 120s after termination"
    fi
else
    fail "Could not locate booking pod to test graceful shutdown"
fi

if [[ -n "$BOOKING_ID" && -n "$TOKEN" && -n "$GATEWAY_IP" ]]; then
    cancel_resp=$(curl -s --max-time 15 -X DELETE -H "Host: booking.apollo.local" \
        -H "Authorization: Bearer $TOKEN" \
        "http://${GATEWAY_IP}/api/bookings/${BOOKING_ID}" 2>/dev/null || echo "")
    if echo "$cancel_resp" | grep -q "Booking cancelled"; then
        pass "Cancelled flagship verification booking $BOOKING_ID"
        BOOKING_ID=""
    else
        fail "Failed to cancel flagship verification booking ${BOOKING_ID}: ${cancel_resp}"
    fi
fi

header "15. Reversible Eviction API & PodDisruptionBudget Enforcement Proof"
info "Testing PDB contract: verifying first eviction succeeds and second is blocked..."
read -r -a BOOKING_PODS <<< "$(kube get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[*].metadata.name}')"
if [[ "${#BOOKING_PODS[@]}" -ge 2 ]]; then
    POD1="${BOOKING_PODS[0]}"
    POD2="${BOOKING_PODS[1]}"
    
    # First eviction: should succeed because minAvailable=1 and 2 are healthy
    evict1_resp=$(kube create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD1}/eviction" -f - <<EOF 2>&1 || true
{
  "apiVersion": "policy/v1",
  "kind": "Eviction",
  "metadata": {
    "name": "${POD1}",
    "namespace": "apollo-airlines-apps"
  }
}
EOF
)
    if [[ "$evict1_resp" == *"Success"* || "$evict1_resp" == *"201"* ]]; then
        pass "First pod eviction ($POD1) permitted by booking-pdb"
    else
        fail "First pod eviction failed unexpectedly: $evict1_resp"
    fi

    # Second eviction immediately after: should be BLOCKED with 429 / DisruptionBudget
    evict2_resp=$(kube create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD2}/eviction" -f - <<EOF 2>&1 || true
{
  "apiVersion": "policy/v1",
  "kind": "Eviction",
  "metadata": {
    "name": "${POD2}",
    "namespace": "apollo-airlines-apps"
  }
}
EOF
)
    if [[ "$evict2_resp" == *"Cannot evict pod as it would violate the pod's disruption budget"* || "$evict2_resp" == *"TooManyRequests"* ]]; then
        pass "PDB enforcement proven: second eviction ($POD2) rejected by booking-pdb (budget exhausted)"
    else
        fail "PDB failed to block second eviction: $evict2_resp"
    fi

    # Prove live traffic still serves HTTP 200 during eviction
    evict_traffic=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -H "Host: booking.apollo.local" "http://${GATEWAY_IP}/healthz" 2>/dev/null || echo "000")
    if [[ "$evict_traffic" == "200" ]]; then
        pass "Traffic survived eviction disruption (booking service returned HTTP 200)"
    else
        fail "Traffic disrupted during eviction (HTTP $evict_traffic)"
    fi

    # Wait for replacement pod to be Ready
    info "Waiting for replacement pod to be Ready..."
    kube rollout status deployment/booking -n apollo-airlines-apps --timeout=60s >/dev/null 2>&1 || true
    booking_healthy=$(kube get pdb booking-pdb -n apollo-airlines-apps -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "0")
    booking_healthy="${booking_healthy:-0}"
    if [[ "$booking_healthy" -ge 2 ]]; then
        pass "booking-pdb fully recovered: currentHealthy=$booking_healthy"
    else
        fail "booking-pdb failed to recover: currentHealthy=$booking_healthy"
    fi
else
    fail "Expected at least 2 booking pods to test eviction"
fi

header "16. Reversible Placement Lab (Topology Spread & Node Taints)"
worker_nodes_total=$(kube get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | wc -l | tr -d ' ')
worker_nodes_used=$(kube get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && $2!=""{print $2}' | sort -u | wc -l | tr -d ' ')
if [[ "$worker_nodes_total" -ge 2 ]]; then
    if [[ "$worker_nodes_used" -ge 2 ]]; then
        pass "topologySpreadConstraints active: booking pods spread across $worker_nodes_used/$worker_nodes_total workers"
    else
        fail "topologySpreadConstraints expected booking across >= 2 workers, found $worker_nodes_used/$worker_nodes_total"
    fi
else
    info "Single worker cluster detected; skipping multi-worker spread assertion ($worker_nodes_used node)"
fi

TARGET_NODE=$(kube get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$TARGET_NODE" ]]; then
    info "Executing reversible taint scheduling gate lab on $TARGET_NODE..."
    kube taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule >/dev/null 2>&1
    taint_val=$(kube get node "$TARGET_NODE" -o jsonpath='{.spec.taints[?(@.key=="apollo11.io/maintenance")].value}' 2>/dev/null || echo "")
    if [[ "$taint_val" == "true" ]]; then
        pass "Reversible taint applied to $TARGET_NODE (NoSchedule)"
    else
        fail "Failed to apply taint to $TARGET_NODE"
    fi

    # Prove reversible taint scheduling gate: an untolerated pod pinned to TARGET_NODE stays Pending/Unschedulable
    kube apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: stage4-taint-probe
  namespace: apollo-airlines-apps
  labels:
    apollo11.io/lab: stage4-taint
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  nodeSelector:
    kubernetes.io/hostname: ${TARGET_NODE}
  containers:
    - name: pause
      image: busybox:1.36
      command: ["sh", "-c", "sleep 5"]
      resources:
        requests: { cpu: 10m, memory: 16Mi }
        limits: { cpu: 10m, memory: 16Mi }
EOF
    probe_reason=""
    for _ in $(seq 1 10); do
        probe_reason=$(kube get pod stage4-taint-probe -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null || echo "")
        if [[ "$probe_reason" == "Unschedulable" ]]; then
            break
        fi
        sleep 1
    done
    if [[ "$probe_reason" == "Unschedulable" ]]; then
        pass "Taint scheduling gate proven: untolerated pod blocked on $TARGET_NODE (Unschedulable)"
    else
        fail "Expected untolerated pod on tainted node $TARGET_NODE to be Unschedulable (got '${probe_reason:-none}')"
    fi
    kube delete pod stage4-taint-probe -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true

    # Remove taint and restore node state
    kube taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule- >/dev/null 2>&1
    taint_check=$(kube get node "$TARGET_NODE" -o jsonpath='{.spec.taints[?(@.key=="apollo11.io/maintenance")].value}' 2>/dev/null || echo "")
    if [[ -z "$taint_check" ]]; then
        pass "Node $TARGET_NODE successfully restored (taint removed)"
    else
        fail "Node $TARGET_NODE still has taint"
    fi
else
    fail "Could not discover a non-control-plane worker node for reversible taint test"
fi

header "17. Stage 4 Proof: Readiness (EndpointSlice, 0 Restarts) vs Liveness (Container Restart)"
kube apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: stage4-probe-lab
  namespace: apollo-airlines-apps
spec:
  selector:
    app: stage4-probe-lab
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: stage4-probe-lab
  namespace: apollo-airlines-apps
  labels:
    app: stage4-probe-lab
spec:
  restartPolicy: Always
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: probe
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command:
        - python3
        - -c
        - |
          import http.server, os, socketserver
          open("/tmp/ready", "w").close()
          open("/tmp/live", "w").close()
          class H(http.server.BaseHTTPRequestHandler):
              def do_GET(self):
                  if self.path == "/ready":
                      ok = os.path.exists("/tmp/ready")
                      self.send_response(200 if ok else 503)
                      self.end_headers()
                      self.wfile.write(b"ready" if ok else b"not ready")
                  elif self.path == "/live":
                      ok = os.path.exists("/tmp/live")
                      self.send_response(200 if ok else 500)
                      self.end_headers()
                      self.wfile.write(b"live" if ok else b"dead")
                  else:
                      self.send_response(200)
                      self.end_headers()
              def log_message(self, *args):
                  pass
          socketserver.TCPServer.allow_reuse_address = True
          with socketserver.TCPServer(("", 8080), H) as s:
              s.serve_forever()
      ports:
        - containerPort: 8080
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 1
        periodSeconds: 2
        failureThreshold: 1
      livenessProbe:
        httpGet:
          path: /live
          port: 8080
        initialDelaySeconds: 2
        periodSeconds: 2
        failureThreshold: 2
      resources:
        requests: { cpu: 20m, memory: 32Mi }
        limits: { cpu: 20m, memory: 32Mi }
EOF

if kube wait --for=condition=Ready pod/stage4-probe-lab -n apollo-airlines-apps --timeout=45s >/dev/null 2>&1; then
    ep_before=$(kube get endpointslices -n apollo-airlines-apps -l kubernetes.io/service-name=stage4-probe-lab -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[*]}{end}' 2>/dev/null || echo "")
    if [[ -n "$ep_before" ]]; then
        pass "Probe lab EndpointSlice initially populated with ready IP ($ep_before)"
    else
        fail "Probe lab EndpointSlice missing ready IP initially"
    fi

    kube exec -n apollo-airlines-apps stage4-probe-lab -- rm -f /tmp/ready >/dev/null 2>&1 || true
    ep_after="pending"
    for _ in $(seq 1 15); do
        ready_cond=$(kube get pod stage4-probe-lab -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        ep_after=$(kube get endpointslices -n apollo-airlines-apps -l kubernetes.io/service-name=stage4-probe-lab -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[*]}{end}' 2>/dev/null || echo "")
        if [[ "$ready_cond" == "False" && -z "$ep_after" ]]; then
            break
        fi
        sleep 2
    done
    restarts_after_ready=$(kube get pod stage4-probe-lab -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "99")
    if [[ -z "$ep_after" && "${restarts_after_ready:-99}" -eq 0 ]]; then
        pass "Readiness failure removed Pod IP from EndpointSlice with 0 container restarts"
    else
        fail "Readiness failure proof failed (ep_after='$ep_after', restarts=$restarts_after_ready)"
    fi

    kube exec -n apollo-airlines-apps stage4-probe-lab -- rm -f /tmp/live >/dev/null 2>&1 || true
    restarts_after_live=0
    for _ in $(seq 1 20); do
        restarts_after_live=$(kube get pod stage4-probe-lab -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
        if [[ "${restarts_after_live:-0}" -ge 1 ]]; then
            break
        fi
        sleep 2
    done
    if [[ "${restarts_after_live:-0}" -ge 1 ]]; then
        pass "Liveness failure triggered kubelet container restart (restartCount=$restarts_after_live)"
    else
        fail "Liveness failure did not increment restartCount (got $restarts_after_live)"
    fi
else
    fail "stage4-probe-lab pod did not become Ready within 45s"
fi
kube delete pod stage4-probe-lab -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true
kube delete service stage4-probe-lab -n apollo-airlines-apps --ignore-not-found >/dev/null 2>&1 || true

header "18. Stage 4 Proof: OOMKill (ExitCode 137) & CPU Throttling (cpu.stat)"
kube apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stage4-oom-probe
  namespace: apollo-airlines-apps
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: oom
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command: ["python3", "-c", "a = bytearray(64 * 1024 * 1024)"]
      resources:
        requests: { cpu: 20m, memory: 16Mi }
        limits: { cpu: 20m, memory: 16Mi }
EOF

oom_reason=""
oom_code=""
for _ in $(seq 1 20); do
    oom_reason=$(kube get pod stage4-oom-probe -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || echo "")
    oom_code=$(kube get pod stage4-oom-probe -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
    if [[ -n "$oom_code" ]]; then
        break
    fi
    sleep 2
done
if [[ "$oom_reason" == "OOMKilled" && "$oom_code" == "137" ]]; then
    pass "OOMKill proof verified: Pod terminated with Reason=OOMKilled and ExitCode=137"
else
    fail "OOMKill proof failed (reason='${oom_reason:-none}', exitCode='${oom_code:-none}')"
fi
kube delete pod stage4-oom-probe -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true

kube apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stage4-cpu-probe
  namespace: apollo-airlines-apps
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: burn
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command:
        - python3
        - -c
        - |
          import time
          end = time.time() + 3.0
          x = 0
          while time.time() < end:
              x += 1
          for p in ("/sys/fs/cgroup/cpu.stat", "/sys/fs/cgroup/cpu/cpu.stat"):
              try:
                  print(open(p).read())
                  break
              except FileNotFoundError:
                  pass
      resources:
        requests: { cpu: 10m, memory: 32Mi }
        limits: { cpu: 10m, memory: 32Mi }
EOF

cpu_phase=""
for _ in $(seq 1 25); do
    cpu_phase=$(kube get pod stage4-cpu-probe -n apollo-airlines-apps -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$cpu_phase" == "Succeeded" || "$cpu_phase" == "Failed" ]]; then
        break
    fi
    sleep 2
done
cpu_stat_out=$(kube logs -n apollo-airlines-apps stage4-cpu-probe 2>/dev/null || echo "")
nr_throttled=$(echo "$cpu_stat_out" | awk '$1=="nr_throttled"{print $2}')
throttled_usec=$(echo "$cpu_stat_out" | awk '$1=="throttled_usec" || $1=="throttled_time"{print $2}')
if [[ "${nr_throttled:-0}" -gt 0 && "${throttled_usec:-0}" -gt 0 ]]; then
    pass "CPU throttling proof verified: nr_throttled=${nr_throttled}, throttled_usec=${throttled_usec}"
else
    fail "CPU throttling proof failed (phase=${cpu_phase}, nr_throttled=${nr_throttled:-0}, throttled_usec=${throttled_usec:-0})"
fi
kube delete pod stage4-cpu-probe -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true

header "19. Stage 4 Proof: Zero-Drop In-Flight Traffic During preStop Rolling Restart"
if [[ -n "$GATEWAY_IP" ]]; then
    ROLL_STOP_FILE=$(mktemp -u)
    ROLL_LOAD_LOG=$(mktemp)
    (
        while [[ ! -f "$ROLL_STOP_FILE" ]]; do
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: booking.apollo.local" "http://${GATEWAY_IP}/healthz" 2>/dev/null || echo "000")
            echo "$code" >> "$ROLL_LOAD_LOG"
            sleep 0.1
        done
    ) &
    ROLL_LOAD_PID=$!
    sleep 1
    kube rollout restart deployment/booking -n apollo-airlines-apps >/dev/null
    if kube rollout status deployment/booking -n apollo-airlines-apps --timeout=120s >/dev/null 2>&1; then
        sleep 1
        touch "$ROLL_STOP_FILE"
        wait "$ROLL_LOAD_PID" 2>/dev/null || true
        ROLL_LOAD_PID=""
        total_reqs=$(wc -l < "$ROLL_LOAD_LOG" | tr -d ' ')
        failed_reqs=$(awk '$1 != "200" {c++} END {print c+0}' "$ROLL_LOAD_LOG")
        if [[ "${total_reqs:-0}" -ge 10 && "${failed_reqs:-1}" -eq 0 ]]; then
            pass "Zero-drop rolling restart proven ($total_reqs/$total_reqs HTTP 200 across booking rollout)"
        else
            fail "Rolling restart dropped requests ($failed_reqs/$total_reqs non-200)"
        fi
    else
        touch "$ROLL_STOP_FILE"
        wait "$ROLL_LOAD_PID" 2>/dev/null || true
        ROLL_LOAD_PID=""
        fail "booking rollout restart did not complete within 120s"
    fi
    rm -f "$ROLL_STOP_FILE" "$ROLL_LOAD_LOG"
    ROLL_STOP_FILE=""
    ROLL_LOAD_LOG=""
else
    fail "GATEWAY_IP unavailable for zero-drop rolling restart proof"
fi

if KUBE_CONTEXT="$CONTEXT" bash "${SCRIPT_DIR}/verify-tls.sh"; then
  pass "trusted HTTPS workflow and hostname rejection"
else
  fail "trusted HTTPS workflow or hostname rejection failed"
fi

header "Verification Summary"
echo "  Total Passed: $PASS"
echo "  Total Failed: $FAIL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "${GREEN}Stage 4 verification succeeded with 0 failures.${NC}"
    exit 0
else
    echo -e "${RED}Stage 4 verification failed with $FAIL failure(s).${NC}"
    exit 1
fi
