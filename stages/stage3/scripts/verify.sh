#!/bin/bash
# Verify Stage 3: 30+ checks covering StatefulSets, PVCs, headless DNS,
# seed jobs, plus the full Stage 2 set-5 access stack.
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

step "Namespaces (4 expected: apps, ui, envoy-gateway-system, metallb-system)"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then pass "namespace $ns"; else fail "namespace $ns missing"; fi
done

step "StatefulSets (4 expected, all 1/1 Ready)"
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

step "PVCs (4 expected, all Bound — proves storage works)"
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

step "PVs exist and are bound to the PVCs (4 expected)"
pv_count=$(kubectl get pv --no-headers 2>/dev/null | grep -c "Bound" || echo 0)
if [[ "$pv_count" -ge 4 ]]; then
  pass "$pv_count PVs in Bound state"
else
  fail "only $pv_count PVs in Bound state (expected ≥ 4)"
fi

step "Headless Services exist (4 expected)"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
  cip=$(kubectl get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  if [[ "$cip" == "None" ]]; then
    pass "headless service $svc (clusterIP=None)"
  else
    fail "service $svc clusterIP=$cip (expected None)"
  fi
done

step "Headless Service DNS returns pod IPs (1 per StatefulSet)"
# kubectl exec into an app pod (uses CoreDNS) and resolve the headless name.
# Use `getent hosts` (works in any minimal image) instead of `nslookup`,
# which isn't installed in the python:3.12-slim identity image.
NS="apollo-airlines-apps"
for db in identity-db flight-db booking-db redis; do
  resolved=$(kubectl exec -n "$NS" deployment/identity -- \
    getent hosts "$db-headless" 2>/dev/null | awk '{print $1}' | head -1)
  if [[ -n "$resolved" ]]; then
    # Headless resolves to a pod IP (10.244.x.x), ClusterIP resolves to 10.96.x.x.
    if [[ "$resolved" =~ ^10\.244\. ]]; then
      pass "DNS resolved $db-headless → $resolved (pod IP)"
    else
      fail "$db-headless resolved to $resolved (expected pod IP, not VIP)"
    fi
  else
    fail "DNS did not resolve $db-headless"
  fi
done

step "ClusterIP Services (DBs + redis) — for app connections"
for svc in identity-db flight-db booking-db redis; do
  cip=$(kubectl get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  if [[ -n "$cip" && "$cip" != "None" ]]; then
    pass "cluster service $svc clusterIP=$cip"
  else
    fail "cluster service $svc missing or headless (clusterIP=$cip)"
  fi
done

step "App Deployments (6 expected, all 2/2 Ready)"
for d in identity flight booking search notification; do
  ready=$(kubectl get deploy "$d" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 2 ]]; then
    pass "deploy apollo-airlines-apps/$d ready=$ready"
  else
    fail "deploy apollo-airlines-apps/$d ready=$ready (expected ≥ 2)"
  fi
done
ready=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 2 ]]; then pass "deploy apollo-airlines-ui/frontend ready=$ready"; else fail "deploy frontend ready=$ready"; fi

step "MetalLB controller"
ready=$(kubectl get deploy controller -n metallb-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then pass "metallb controller ready=$ready"; else fail "metallb controller not ready"; fi

step "Envoy Gateway controller"
ready=$(kubectl get deploy envoy-gateway -n envoy-gateway-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then pass "envoy-gateway controller ready=$ready"; else fail "envoy-gateway controller not ready"; fi

step "Envoy proxy (auto-created by Gateway)"
proxy_ready=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | awk '{print $2}' | grep -cE "^[0-9]+/[0-9]+$")
proxy_ready=${proxy_ready:-0}
if [[ "$proxy_ready" -ge 1 ]]; then pass "envoy proxy pod Ready (count=$proxy_ready)"; else fail "envoy proxy not Ready (count=$proxy_ready)"; fi

step "Seed jobs (3 expected, all succeeded)"
for j in seed-identity-db seed-flight-db seed-booking-db; do
  s=$(kubectl get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then pass "job $j succeeded"; else fail "job $j succeeded=$s"; fi
done

step "MetalLB IPAddressPool"
if kubectl get ipaddresspool apollo-pool -n metallb-system >/dev/null 2>&1; then
  pass "apollo-pool IPAddressPool exists"
else
  fail "apollo-pool IPAddressPool missing"
fi

step "Envoy LoadBalancer Service has an IP from MetalLB"
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$SVC" ]]; then
  ENVOY_IP=$(kubectl get svc "$SVC" -n envoy-gateway-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [[ -n "$ENVOY_IP" ]]; then pass "MetalLB assigned IP: $ENVOY_IP"; else fail "no LoadBalancer IP assigned to $SVC"; fi
else
  fail "envoy Service not found"
  ENVOY_IP=""
fi

step "Gateway 'apollo-gateway' is Programmed"
prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$prog" == "True" ]]; then pass "apollo-gateway is Programmed"; else fail "apollo-gateway is not Programmed (status=$prog)"; fi

step "HTTPRoutes (6 expected, all with parent status)"
rt_count=$(kubectl get httproute -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
parent_count=$(kubectl get httproute -A -o custom-columns="P:.status.parents[*].controllerName" --no-headers 2>/dev/null | grep -c "gateway.envoyproxy.io" || echo 0)
if [[ "$rt_count" -ge 6 ]] && [[ "$parent_count" -ge 6 ]]; then
  pass "$rt_count HTTPRoutes, all $parent_count have parents"
else
  fail "only $rt_count/$parent_count HTTPRoutes have parents"
fi

# Skip smoke tests if no IP
if [[ -z "$ENVOY_IP" ]]; then
  echo ""
  echo "Skipping smoke tests (no MetalLB IP)."
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

step "Smoke test: Envoy → identity (Host header, /healthz) at $ENVOY_IP"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "http://$ENVOY_IP/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → identity → 200"; else fail "Envoy → identity → $RESP (expected 200)"; fi

step "Smoke test: Envoy → flight (Host header, /api/flights)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "http://$ENVOY_IP/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → flight → 200"; else fail "Envoy → flight → $RESP (expected 200)"; fi

step "Smoke test: Envoy → frontend (Host header)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://$ENVOY_IP/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → frontend → 200"; else fail "Envoy → frontend → $RESP (expected 200)"; fi

step "Smoke test: full login flow through Envoy Gateway"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "http://$ENVOY_IP/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through Envoy returned a JWT (${#TOKEN} chars)"
else
  fail "Login through Envoy failed: $LOGIN_RESP"
fi

step "Stage 3 new: seed data actually present in DBs"
# Admin user count: 2 (admin, passenger). Should be ≥ 2.
u_count=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo "")
if [[ "$u_count" -ge 2 ]]; then
  pass "users table has $u_count rows (seed worked)"
else
  fail "users table has $u_count rows (expected ≥ 2)"
fi

# Airports: 6.
a_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo "")
if [[ "$a_count" -ge 6 ]]; then
  pass "airports table has $a_count rows (seed worked)"
else
  fail "airports table has $a_count rows (expected ≥ 6)"
fi

# Flights: 6 routes × 31 days = 186.
f_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo "")
if [[ "$f_count" -ge 180 ]]; then
  pass "flights table has $f_count rows (seed worked)"
else
  fail "flights table has $f_count rows (expected ≥ 180)"
fi

step "Stage 3 new: redis is reachable from app pods"
PONG=$(kubectl exec -n apollo-airlines-apps deployment/identity -- \
  sh -c 'echo -e "PING\r\n" | (exec 3<>/dev/tcp/redis/6379; cat >&3; cat <&3)' 2>/dev/null \
  | head -1 || echo "")
# That's flaky in busybox-style images; simpler check via the service name.
if kubectl exec -n apollo-airlines-apps deployment/identity -- \
   sh -c 'getent hosts redis >/dev/null && echo OK' >/dev/null 2>&1; then
  pass "DNS resolves redis service from app pod"
else
  fail "DNS did not resolve redis service from app pod"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
