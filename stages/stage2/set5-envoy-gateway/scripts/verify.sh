#!/bin/bash
# Verify Set 5: Envoy Gateway API + MetalLB.
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

step "Namespaces (4 expected: apps, ui, envoy-gateway-system, metallb-system)"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then pass "namespace $ns"; else fail "namespace $ns missing"; fi
done

step "Deployments (10 expected)"
EXPECTED_DEPS=(
  "apollo-airlines-apps:identity-db"
  "apollo-airlines-apps:flight-db"
  "apollo-airlines-apps:booking-db"
  "apollo-airlines-apps:redis"
  "apollo-airlines-apps:identity"
  "apollo-airlines-apps:flight"
  "apollo-airlines-apps:booking"
  "apollo-airlines-apps:search"
  "apollo-airlines-apps:notification"
  "apollo-airlines-ui:frontend"
)
for d in "${EXPECTED_DEPS[@]}"; do
  ns="${d%%:*}"; name="${d##*:}"
  ready=$(kubectl get deploy "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -gt 0 ]]; then
    pass "deploy $ns/$name ready=$ready"
  else
    fail "deploy $ns/$name not ready"
  fi
done

step "MetalLB controller"
if kubectl get deploy controller -n metallb-system >/dev/null 2>&1; then
  ready=$(kubectl get deploy controller -n metallb-system -o jsonpath='{.status.readyReplicas}')
  if [[ "$ready" -ge 1 ]]; then pass "metallb controller ready=$ready"; else fail "metallb controller not ready"; fi
else
  fail "metallb controller missing"
fi

step "Envoy Gateway controller"
if kubectl get deploy envoy-gateway -n envoy-gateway-system >/dev/null 2>&1; then
  ready=$(kubectl get deploy envoy-gateway -n envoy-gateway-system -o jsonpath='{.status.readyReplicas}')
  if [[ "$ready" -ge 1 ]]; then pass "envoy-gateway controller ready=$ready"; else fail "envoy-gateway controller not ready"; fi
else
  fail "envoy-gateway controller missing"
fi

step "Envoy proxy (auto-created by Gateway)"
proxy_ready=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | awk '{print $2}' | grep -cE "^[0-9]+/[0-9]+$" || echo 0)
proxy_ready=${proxy_ready:-0}
if [[ "$proxy_ready" -ge 1 ]]; then pass "envoy proxy pod Ready (count=$proxy_ready)"; else fail "envoy proxy not Ready"; fi

step "Init jobs (3 expected, all succeeded)"
for j in init-identity-db init-flight-db init-booking-db; do
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

step "GatewayClass 'eg' is the Envoy Gateway built-in"
gc=$(kubectl get gatewayclass eg -o jsonpath='{.spec.controllerName}' 2>/dev/null || echo "")
if [[ "$gc" == "gateway.envoyproxy.io/gatewayclass-controller" ]]; then
  pass "GatewayClass eg exists with controller=$gc"
else
  fail "GatewayClass eg missing or wrong controller: $gc"
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
if [[ -n "$TOKEN" ]]; then pass "Login through Envoy returned a JWT (${#TOKEN} chars)"; else fail "Login through Envoy failed: $LOGIN_RESP"; fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
