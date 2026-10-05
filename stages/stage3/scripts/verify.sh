#!/usr/bin/env bash

set -euo pipefail

CONTEXT="${1:-${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}}"

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 3 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

step "1. Core Namespaces"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    pass "Namespace $ns exists"
  else
    fail "Namespace $ns missing"
  fi
done

step "2. ServiceAccounts (Token Automount Security)"
EXPECTED_SAS=(identity-db flight-db booking-db redis identity flight booking search notification init-identity-db init-flight-db init-booking-db)
for sa in "${EXPECTED_SAS[@]}"; do
  automount=$(kube get sa "$sa" -n apollo-airlines-apps -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "not-found")
  if [[ "$automount" == "false" ]]; then
    pass "SA apollo-airlines-apps/$sa exists (automount=false)"
  else
    fail "SA apollo-airlines-apps/$sa invalid or missing (automount=$automount)"
  fi
done

frontend_automount=$(kube get sa frontend -n apollo-airlines-ui -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "not-found")
if [[ "$frontend_automount" == "false" ]]; then
  pass "SA apollo-airlines-ui/frontend exists (automount=false)"
else
  fail "SA apollo-airlines-ui/frontend invalid or missing (automount=$frontend_automount)"
fi

step "3. StatefulSets & Pods (Stable Workload Identity)"
for sts in identity-db flight-db booking-db redis; do
  ready=$(kube get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "${ready:-0}" -ge 1 ]]; then
    pass "StatefulSet apollo-airlines-apps/$sts ready (replicas=$ready)"
  else
    fail "StatefulSet apollo-airlines-apps/$sts not ready"
  fi
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  status=$(kube get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$status" == "True" ]]; then
    pass "StatefulSet Pod apollo-airlines-apps/$pod is Ready"
  else
    fail "StatefulSet Pod apollo-airlines-apps/$pod not Ready"
  fi
done

step "4. Storage Provisioning (PVCs & PersistentVolumes)"
EXPECTED_PVCS=(pg-data-identity-db-0 pg-data-flight-db-0 pg-data-booking-db-0 redis-data-redis-0)
for pvc in "${EXPECTED_PVCS[@]}"; do
  phase=$(kube get pvc "$pvc" -n apollo-airlines-apps -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  mode=$(kube get pvc "$pvc" -n apollo-airlines-apps -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo "")
  size=$(kube get pvc "$pvc" -n apollo-airlines-apps -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "")
  if [[ "$phase" == "Bound" && "$mode" == "ReadWriteOnce" && "$size" == "1Gi" ]]; then
    pass "PVC $pvc is Bound (ReadWriteOnce, 1Gi)"
  else
    fail "PVC $pvc invalid: phase=$phase mode=$mode size=$size"
  fi
done

pv_count=$(kube get pv --no-headers 2>/dev/null | grep -c "Bound" || echo 0)
if [[ "$pv_count" -ge 4 ]]; then
  pass "Cluster has $pv_count Bound PersistentVolumes backing StatefulSet storage"
else
  fail "Insufficient Bound PVs ($pv_count found, expected >= 4)"
fi

step "5. Headless Services & Stable DNS Inspection"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
  cip=$(kube get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  if [[ "$cip" == "None" ]]; then
    pass "Headless Service $svc has clusterIP=None"
  else
    fail "Service $svc clusterIP is not None ($cip)"
  fi
done

for db in identity-db flight-db booking-db redis; do
  resolved=$(kube exec -n apollo-airlines-apps deployment/identity -- getent hosts "${db}-headless" 2>/dev/null | awk '{print $1}' | head -1 || echo "")
  if [[ -n "$resolved" && "$resolved" =~ ^10\.244\. ]]; then
    pass "CoreDNS resolves ${db}-headless directly to pod IP: $resolved"
  else
    fail "Failed to resolve ${db}-headless to pod IP: $resolved"
  fi
done

step "6. Application Workloads & Seed Jobs"
for dep in identity flight booking search notification; do
  ready=$(kube get deploy "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "${ready:-0}" -ge 2 ]]; then
    pass "Deployment apollo-airlines-apps/$dep ready ($ready replicas)"
  else
    fail "Deployment apollo-airlines-apps/$dep not ready"
  fi
done

ui_ready=$(kube get deploy frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "${ui_ready:-0}" -ge 2 ]]; then
  pass "Deployment apollo-airlines-ui/frontend ready ($ui_ready replicas)"
else
  fail "Deployment apollo-airlines-ui/frontend not ready"
fi

for j in seed-identity-db seed-flight-db seed-booking-db; do
  s=$(kube get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then
    pass "Database seed job apollo-airlines-apps/$j completed"
  else
    fail "Database seed job apollo-airlines-apps/$j not completed"
  fi
done

step "7. Database Seed Integrity"
u_count=$(kube exec -n apollo-airlines-apps identity-db-0 -- psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo 0)
if [[ "${u_count:-0}" -ge 2 ]]; then
  pass "identity-db schema initialized via entrypoint; users table has $u_count rows"
else
  fail "identity-db seed count invalid ($u_count)"
fi

a_count=$(kube exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo 0)
if [[ "${a_count:-0}" -ge 6 ]]; then
  pass "flight-db schema initialized via entrypoint; airports table has $a_count rows"
else
  fail "flight-db airports count invalid ($a_count)"
fi

f_count=$(kube exec -n apollo-airlines-apps flight-db-0 -- psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo 0)
if [[ "${f_count:-0}" -ge 180 ]]; then
  pass "flight-db flights table has $f_count rows (31-day inventory seeded)"
else
  fail "flight-db flights count invalid ($f_count)"
fi

step "8. Envoy Gateway & MetalLB Access Stack"
gc_status=$(kube get gatewayclass eg -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
if [[ "$gc_status" == "True" ]]; then
  pass "GatewayClass 'eg' accepted"
else
  fail "GatewayClass 'eg' not accepted"
fi

gw_prog=$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "False")
gw_acc=$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
if [[ "$gw_prog" == "True" && "$gw_acc" == "True" ]]; then
  pass "Gateway apollo-gateway is Accepted and Programmed"
else
  fail "Gateway apollo-gateway status invalid (Accepted=$gw_acc, Programmed=$gw_prog)"
fi

for route in identity flight booking search notification; do
  route_acc=$(kube get httproute "$route" -n apollo-airlines-apps -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
  if [[ "$route_acc" =~ "True" ]]; then
    pass "HTTPRoute apollo-airlines-apps/$route accepted"
  else
    fail "HTTPRoute apollo-airlines-apps/$route not accepted"
  fi
done

frontend_route_acc=$(kube get httproute frontend -n apollo-airlines-ui -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
if [[ "$frontend_route_acc" =~ "True" ]]; then
  pass "HTTPRoute apollo-airlines-ui/frontend accepted"
else
  fail "HTTPRoute apollo-airlines-ui/frontend not accepted"
fi

EG_IP=$(kube get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$EG_IP" ]]; then
  pass "MetalLB assigned LoadBalancer IP: $EG_IP"
else
  fail "Envoy Proxy missing LoadBalancer IP"
fi

if [[ -n "$EG_IP" ]]; then
  for host in "identity.apollo.local" "flight.apollo.local" "booking.apollo.local" "search.apollo.local"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" --connect-timeout 2 "http://${EG_IP}/healthz" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
      pass "Envoy Gateway HTTPRoute to $host returned HTTP 200"
    else
      fail "Envoy Gateway HTTPRoute to $host failed (HTTP $code)"
    fi
  done

  fe_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" --connect-timeout 2 "http://${EG_IP}/" 2>/dev/null || echo "000")
  if [[ "$fe_code" == "200" ]]; then
    pass "Envoy Gateway frontend HTTPRoute returned HTTP 200"
  else
    fail "Envoy Gateway frontend route failed (HTTP $fe_code)"
  fi
fi

step "9. Flagship Workflow & Stateful Data Survival Proof"
login_resp=$(curl -s -X POST "http://${EG_IP}/api/users/login" \
  -H "Host: identity.apollo.local" \
  -H "Content-Type: application/json" \
  -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || echo "")
TOKEN=$(echo "$login_resp" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "")
if [[ -n "$TOKEN" ]]; then
  pass "Passenger login succeeded and returned JWT"
else
  fail "Passenger login failed: $login_resp"
fi

flights_resp=$(curl -s -H "Host: flight.apollo.local" "http://${EG_IP}/api/flights" 2>/dev/null || echo "")
FLIGHT_ID=$(echo "$flights_resp" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$FLIGHT_ID" ]]; then
  pass "Query flight inventory returned valid flight ID: $FLIGHT_ID"
else
  fail "Failed to query flight inventory: $flights_resp"
fi

REQ_ID="stage3-verify-${RANDOM}-${RANDOM}"
booking_resp=$(curl -s -X POST "http://${EG_IP}/api/bookings" \
  -H "Host: booking.apollo.local" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: ${REQ_ID}" \
  -d "{\"flightId\":\"${FLIGHT_ID}\"}" 2>/dev/null || echo "")
BOOKING_ID=$(echo "$booking_resp" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "")

if [[ -n "$BOOKING_ID" ]]; then
  pass "Booking created successfully via flagship workflow (id: $BOOKING_ID)"
else
  fail "Booking creation failed: $booking_resp"
fi

info "Executing reversible failure experiment: Deleting pod booking-db-0 to test data persistence..."
kube delete pod booking-db-0 -n apollo-airlines-apps --wait=true >/dev/null 2>&1
kube wait --for=condition=Ready pod/booking-db-0 -n apollo-airlines-apps --timeout=60s >/dev/null 2>&1

persisted_booking=$(kube exec -n apollo-airlines-apps booking-db-0 -- psql -U postgres -d booking -tAc "SELECT id FROM bookings WHERE id='${BOOKING_ID}';" 2>/dev/null || echo "")
if [[ "$persisted_booking" == "$BOOKING_ID" ]]; then
  pass "Data survival proven: booking record persisted across booking-db-0 Pod restart via PVC"
else
  fail "Data lost! Booking $BOOKING_ID not found after pod recreation"
fi

# Clean up verified booking
curl -s -X DELETE "http://${EG_IP}/api/bookings/${BOOKING_ID}" \
  -H "Host: booking.apollo.local" \
  -H "Authorization: Bearer ${TOKEN}" >/dev/null 2>&1 || true

if KUBE_CONTEXT="${CONTEXT:-${CURRENT_CTX:-}}" bash "$(dirname "${BASH_SOURCE[0]}")/verify-tls.sh"; then
  pass "trusted HTTPS workflow and hostname rejection"
else
  fail "trusted HTTPS workflow or hostname rejection failed"
fi

step "Verification Summary"
echo -e "  Total Passed: ${GREEN}${PASS}${NC}"
echo -e "  Total Failed: ${RED}${FAIL}${NC}"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo -e "\n${GREEN}Stage 3 verification succeeded with 0 failures.${NC}\n"
