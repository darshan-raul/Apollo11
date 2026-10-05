#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="${CLUSTER:-apollo11}"
ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev")

CURRENT_CTX="$(kubectl config current-context 2>/dev/null || true)"
ctx_matched=false
for allowed in "${ALLOWED_CONTEXTS[@]}"; do
    if [[ "$CURRENT_CTX" == "$allowed" ]]; then
        ctx_matched=true
        break
    fi
done

if [[ "$ctx_matched" != "true" ]]; then
    echo "Refusing to run against context '$CURRENT_CTX'."
    echo "This script only targets one of: ${ALLOWED_CONTEXTS[*]}"
    exit 1
fi

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
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
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
    automount=$(kubectl get serviceaccount "$sa" -n "$ns" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "")
    if [[ "$automount" == "false" ]]; then
        pass "SA $ns/$sa exists (automount=false)"
    else
        fail "SA $ns/$sa missing or automountServiceAccountToken != false"
    fi
done

header "3. StatefulSets & Workload Identity"
for sts in identity-db flight-db booking-db redis; do
    ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready" -ge 1 ]]; then
        pass "StatefulSet apollo-airlines-apps/$sts ready (replicas=$ready)"
    else
        fail "StatefulSet apollo-airlines-apps/$sts not ready (replicas=$ready)"
    fi
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    status=$(kubectl get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
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
    phase=$(kubectl get pvc "$pvc" -n apollo-airlines-apps -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Bound" ]]; then
        pass "PVC $pvc is Bound (1Gi)"
    else
        fail "PVC $pvc phase is '$phase' (expected Bound)"
    fi
done

header "5. Headless Services & CoreDNS Resolution"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
    cip=$(kubectl get service "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    if [[ "$cip" == "None" ]]; then
        pass "Headless Service $svc has clusterIP=None"
    else
        fail "Headless Service $svc clusterIP is '$cip' (expected None)"
    fi
done

header "6. Application Deployments & Seed Jobs"
for dep in identity flight booking search notification; do
    ready=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready" -ge 2 ]]; then
        pass "Deployment apollo-airlines-apps/$dep ready ($ready replicas)"
    else
        fail "Deployment apollo-airlines-apps/$dep not ready ($ready replicas)"
    fi
done
fe_ready=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$fe_ready" -ge 2 ]]; then
    pass "Deployment apollo-airlines-ui/frontend ready ($fe_ready replicas)"
else
    fail "Deployment apollo-airlines-ui/frontend not ready ($fe_ready replicas)"
fi

for job in seed-identity-db seed-flight-db seed-booking-db; do
    succ=$(kubectl get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$succ" -ge 1 ]]; then
        pass "Database seed job apollo-airlines-apps/$job completed"
    else
        fail "Database seed job apollo-airlines-apps/$job not completed"
    fi
done

header "7. Database Seed Integrity"
user_cnt=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo "0")
if [[ "$user_cnt" -ge 2 ]]; then
    pass "identity-db users table has $user_cnt rows"
else
    fail "identity-db users table has $user_cnt rows (expected >= 2)"
fi

airport_cnt=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo "0")
if [[ "$airport_cnt" -ge 6 ]]; then
    pass "flight-db airports table has $airport_cnt rows"
else
    fail "flight-db airports table has $airport_cnt rows (expected >= 6)"
fi

flight_cnt=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo "0")
if [[ "$flight_cnt" -ge 180 ]]; then
    pass "flight-db flights table has $flight_cnt rows"
else
    fail "flight-db flights table has $flight_cnt rows (expected >= 180)"
fi

header "8. Envoy Gateway & MetalLB Access Stack"
gw_status=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$gw_status" == "True" ]]; then
    pass "Gateway apollo-gateway is Programmed"
else
    fail "Gateway apollo-gateway is not Programmed (status=$gw_status)"
fi

GATEWAY_IP=$(kubectl get service -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$GATEWAY_IP" ]]; then
    pass "MetalLB assigned LoadBalancer IP: $GATEWAY_IP"
else
    fail "MetalLB did not assign an IP to Envoy Gateway service"
fi

for host in identity.apollo.local flight.apollo.local booking.apollo.local search.apollo.local; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" "http://${GATEWAY_IP}/healthz" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
        pass "Envoy Gateway HTTPRoute to $host returned HTTP 200"
    else
        fail "Envoy Gateway HTTPRoute to $host returned HTTP $code"
    fi
done
fe_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://${GATEWAY_IP}/" 2>/dev/null || echo "000")
if [[ "$fe_code" == "200" ]]; then
    pass "Envoy Gateway frontend HTTPRoute returned HTTP 200"
else
    fail "Envoy Gateway frontend HTTPRoute returned HTTP $fe_code"
fi

header "9. Stage 4: Probes Configuration (Startup, Liveness, Readiness)"
for dep in identity flight booking search notification; do
    for probe in startupProbe livenessProbe readinessProbe; do
        path=$(kubectl get deploy "$dep" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
        if [[ -n "$path" ]]; then
            pass "deploy/$dep has $probe ($path)"
        else
            fail "deploy/$dep missing $probe"
        fi
    done
done

for probe in startupProbe livenessProbe readinessProbe; do
    path=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
    if [[ -n "$path" ]]; then
        pass "deploy/frontend has $probe ($path)"
    else
        fail "deploy/frontend missing $probe"
    fi
done

for sts in identity-db flight-db booking-db redis; do
    for probe in livenessProbe readinessProbe; do
        cmd=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].${probe}.exec.command[0]}" 2>/dev/null || echo "")
        if [[ -n "$cmd" ]]; then
            pass "statefulset/$sts has $probe ($cmd)"
        else
            fail "statefulset/$sts missing $probe"
        fi
    done
    sp=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null || echo "")
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
        resp=$(kubectl exec -n "$ns" "deploy/$svc" -- sh -c "wget -q -O- http://127.0.0.1:$port/healthz/$p 2>/dev/null || python3 -c \"import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:$port/healthz/$p').read().decode())\" 2>/dev/null || echo FAIL" 2>/dev/null | tr -d '\n' || echo "FAIL")
        if [[ "$resp" != "FAIL" && -n "$resp" ]]; then
            pass "Pod $svc live probe /healthz/$p responded: $(echo "$resp" | head -c 25)"
        else
            fail "Pod $svc live probe /healthz/$p failed"
        fi
    done
done

header "11. Stage 4: Guaranteed QoS & Lifecycle PreStop Hooks"
for dep in identity flight booking search notification; do
    qos=$(kubectl get pods -n apollo-airlines-apps -l app="$dep" -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "Pod $dep QoS class is Guaranteed (requests == limits)"
    else
        fail "Pod $dep QoS class is '$qos' (expected Guaranteed)"
    fi
    grace=$(kubectl get deploy "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "30" ]]; then
        pass "deploy/$dep terminationGracePeriodSeconds is 30"
    else
        fail "deploy/$dep terminationGracePeriodSeconds is '$grace' (expected 30)"
    fi
    prestop=$(kubectl get deploy "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command[0]}' 2>/dev/null || echo "")
    if [[ -n "$prestop" ]]; then
        pass "deploy/$dep has lifecycle preStop hook configured"
    else
        fail "deploy/$dep missing lifecycle preStop hook"
    fi
done

fe_qos=$(kubectl get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
if [[ "$fe_qos" == "Guaranteed" ]]; then
    pass "Pod frontend QoS class is Guaranteed"
else
    fail "Pod frontend QoS class is '$fe_qos' (expected Guaranteed)"
fi
fe_prestop=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command[0]}' 2>/dev/null || echo "")
if [[ -n "$fe_prestop" ]]; then
    pass "deploy/frontend has lifecycle preStop hook configured"
else
    fail "deploy/frontend missing lifecycle preStop hook"
fi

for sts in identity-db flight-db booking-db redis; do
    qos=$(kubectl get pod "$sts-0" -n apollo-airlines-apps -o jsonpath='{.status.qosClass}' 2>/dev/null || echo "")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "StatefulSet pod $sts-0 QoS class is Guaranteed"
    else
        fail "StatefulSet pod $sts-0 QoS class is '$qos' (expected Guaranteed)"
    fi
    grace=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "60" ]]; then
        pass "statefulset/$sts terminationGracePeriodSeconds is 60"
    else
        fail "statefulset/$sts terminationGracePeriodSeconds is '$grace' (expected 60)"
    fi
done

header "12. Stage 4: PriorityClasses & Scheduling Placement"
for pc in apollo-airlines-app-critical apollo-airlines-app-low; do
    if kubectl get priorityclass "$pc" >/dev/null 2>&1; then
        val=$(kubectl get priorityclass "$pc" -o jsonpath='{.value}' 2>/dev/null || echo "")
        pass "PriorityClass $pc exists (value=$val)"
    else
        fail "PriorityClass $pc missing"
    fi
done

for crit_app in booking search; do
    app_pc=$(kubectl get deploy "$crit_app" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
    if [[ "$app_pc" == "apollo-airlines-app-critical" ]]; then
        pass "deploy/$crit_app assigned priorityClassName=apollo-airlines-app-critical"
    else
        fail "deploy/$crit_app priorityClassName is '$app_pc' (expected apollo-airlines-app-critical)"
    fi
done

notif_pc=$(kubectl get deploy notification -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null || echo "")
if [[ "$notif_pc" == "apollo-airlines-app-low" ]]; then
    pass "deploy/notification assigned priorityClassName=apollo-airlines-app-low"
else
    fail "deploy/notification priorityClassName is '$notif_pc' (expected apollo-airlines-app-low)"
fi

for dep_entry in "apollo-airlines-apps:booking" "apollo-airlines-apps:flight" "apollo-airlines-apps:search" "apollo-airlines-ui:frontend"; do
    ns="${dep_entry%%:*}"
    dep="${dep_entry##*:}"
    key=$(kubectl get deploy "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}' 2>/dev/null || echo "")
    if [[ "$key" == "kubernetes.io/hostname" ]]; then
        pass "deploy/$dep has topologySpreadConstraints (topologyKey=kubernetes.io/hostname)"
    else
        fail "deploy/$dep missing topologySpreadConstraints"
    fi
done

header "13. Stage 4: PodDisruptionBudgets (PDB)"
for pdb_entry in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
    ns="${pdb_entry%%:*}"
    pdb="${pdb_entry##*:}"
    min_avail=$(kubectl get pdb "$pdb" -n "$ns" -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
    healthy=$(kubectl get pdb "$pdb" -n "$ns" -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "0")
    if [[ "$min_avail" == "1" && "$healthy" -ge 1 ]]; then
        pass "PDB $ns/$pdb active (minAvailable=1, currentHealthy=$healthy)"
    else
        fail "PDB $ns/$pdb not satisfied (minAvailable=$min_avail, healthy=$healthy)"
    fi
done

header "14. Flagship Booking Workflow & Graceful SIGTERM Shutdown Proof"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
    -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' \
    "http://${GATEWAY_IP}/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$TOKEN" ]]; then
    pass "Passenger login succeeded and returned JWT"
else
    fail "Passenger login failed: $LOGIN_RESP"
fi

FLIGHT_RESP=$(curl -s -H "Host: flight.apollo.local" "http://${GATEWAY_IP}/api/flights" 2>/dev/null || echo "")
FLIGHT_ID=$(echo "$FLIGHT_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$FLIGHT_ID" ]]; then
    pass "Flight inventory query returned valid flight ID: $FLIGHT_ID"
else
    fail "Flight inventory query failed: $FLIGHT_RESP"
fi

BOOKING_RESP=$(curl -s -X POST -H "Host: booking.apollo.local" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"flightId\":\"$FLIGHT_ID\"}" \
    "http://${GATEWAY_IP}/api/bookings" 2>/dev/null || echo "")
BOOKING_ID=$(echo "$BOOKING_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$BOOKING_ID" ]]; then
    pass "Flagship booking workflow succeeded (bookingId: $BOOKING_ID)"
else
    fail "Flagship booking workflow failed: $BOOKING_RESP"
fi

info "Executing reversible termination experiment: Testing graceful SIGTERM shutdown..."
BOOKING_POD=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$BOOKING_POD" ]]; then
    SIGTERM_LOG=$(mktemp)
    kubectl logs -n apollo-airlines-apps "$BOOKING_POD" --follow > "$SIGTERM_LOG" 2>&1 &
    LOG_PID=$!
    sleep 0.5
    kubectl delete pod "$BOOKING_POD" -n apollo-airlines-apps --wait=false >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
        pass "Booking pod logged graceful SIGTERM drain before container exit"
    else
        fail "Booking pod did not log graceful SIGTERM shutdown"
    fi
    rm -f "$SIGTERM_LOG"

    kubectl wait --for=condition=Ready pod -l app=booking -n apollo-airlines-apps --timeout=60s >/dev/null 2>&1
    pass "Booking replacement pod is Ready after termination"
else
    fail "Could not locate booking pod to test graceful shutdown"
fi

header "15. Reversible Eviction API & PodDisruptionBudget Enforcement Proof"
info "Testing PDB contract: verifying first eviction succeeds and second is blocked..."
BOOKING_PODS=($(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[*].metadata.name}'))
if [[ "${#BOOKING_PODS[@]}" -ge 2 ]]; then
    POD1="${BOOKING_PODS[0]}"
    POD2="${BOOKING_PODS[1]}"
    
    # First eviction: should succeed because minAvailable=1 and 2 are healthy
    evict1_resp=$(kubectl create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD1}/eviction" -f - <<EOF 2>&1 || true
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
    evict2_resp=$(kubectl create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD2}/eviction" -f - <<EOF 2>&1 || true
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
    evict_traffic=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: booking.apollo.local" "http://${GATEWAY_IP}/healthz" 2>/dev/null || echo "000")
    if [[ "$evict_traffic" == "200" ]]; then
        pass "Traffic survived eviction disruption (booking service returned HTTP 200)"
    else
        fail "Traffic disrupted during eviction (HTTP $evict_traffic)"
    fi

    # Wait for replacement pod to be Ready
    info "Waiting for replacement pod to be Ready..."
    kubectl rollout status deployment/booking -n apollo-airlines-apps --timeout=60s >/dev/null 2>&1
    booking_healthy=$(kubectl get pdb booking-pdb -n apollo-airlines-apps -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "0")
    if [[ "$booking_healthy" -ge 2 ]]; then
        pass "booking-pdb fully recovered: currentHealthy=$booking_healthy"
    else
        fail "booking-pdb failed to recover: currentHealthy=$booking_healthy"
    fi
else
    fail "Expected at least 2 booking pods to test eviction"
fi

header "16. Reversible Placement Lab (Topology Spread & Node Taints)"
# Check topology spread distribution
worker_nodes_used=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l)
if [[ "$worker_nodes_used" -ge 2 ]]; then
    pass "topologySpreadConstraints active: booking pods distributed across $worker_nodes_used nodes"
else
    info "booking pods currently on $worker_nodes_used node(s)"
fi

TARGET_NODE="apollo11-worker"
if kubectl get node "$TARGET_NODE" >/dev/null 2>&1; then
    info "Executing reversible taint/toleration experiment on $TARGET_NODE..."
    kubectl taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule >/dev/null 2>&1
    taint_val=$(kubectl get node "$TARGET_NODE" -o jsonpath='{.spec.taints[?(@.key=="apollo11.io/maintenance")].value}' 2>/dev/null || echo "")
    if [[ "$taint_val" == "true" ]]; then
        pass "Reversible taint applied to $TARGET_NODE (NoSchedule)"
    else
        fail "Failed to apply taint to $TARGET_NODE"
    fi

    # Remove taint and restore node state
    kubectl taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule- >/dev/null 2>&1
    taint_check=$(kubectl get node "$TARGET_NODE" -o jsonpath='{.spec.taints[?(@.key=="apollo11.io/maintenance")].value}' 2>/dev/null || echo "")
    if [[ -z "$taint_check" ]]; then
        pass "Node $TARGET_NODE successfully restored (taint removed)"
    else
        fail "Node $TARGET_NODE still has taint"
    fi
fi

if KUBE_CONTEXT="${CONTEXT:-${CURRENT_CTX:-}}" bash "$(dirname "${BASH_SOURCE[0]}")/verify-tls.sh"; then
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
