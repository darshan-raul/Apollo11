#!/bin/bash
# Verify Set 3: Envoy Gateway API routes by Host header.
# Requires port-forward to be running:
#   kubectl port-forward -n apollo-airlines-apps svc/apollo-gateway 8888:80
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

PORT="${PORT:-8888}"
ENTRY="http://localhost:${PORT}"

step "Namespaces (3 expected: apps, ui, envoy-gateway-system)"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then pass "namespace $ns"; else fail "namespace $ns missing"; fi
done

step "Deployments (10 app/infra + 1 envoy controller)"
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
    fail "deploy $ns/$name not ready (ready=$ready)"
  fi
done

step "Envoy Gateway controller"
if kubectl get deploy envoy-gateway -n envoy-gateway-system >/dev/null 2>&1; then
  ready=$(kubectl get deploy envoy-gateway -n envoy-gateway-system -o jsonpath='{.status.readyReplicas}')
  if [[ "$ready" -ge 1 ]]; then
    pass "envoy-gateway controller ready=$ready"
  else
    fail "envoy-gateway controller not ready"
  fi
else
  fail "envoy-gateway controller missing"
fi

step "Envoy proxy (auto-created by Gateway, runs in envoy-gateway-system)"
# Envoy proxy pods have 2/2 Ready (envoy + maybe a sidecar)
proxy_count=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | wc -l | tr -d ' ')
proxy_ready=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | awk '{print $2}' | grep -cE "^[0-9]+/[0-9]+$" || echo 0)
proxy_ready=${proxy_ready:-0}
if [[ "$proxy_ready" -ge 1 ]]; then
  pass "envoy proxy pod Ready (count=$proxy_ready)"
else
  fail "envoy proxy not Ready (count=$proxy_ready)"
fi

step "Init jobs (3 expected, all succeeded)"
for j in init-identity-db init-flight-db init-booking-db; do
  s=$(kubectl get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then pass "job $j succeeded"; else fail "job $j succeeded=$s"; fi
done

step "GatewayClass 'eg' is the Envoy Gateway built-in"
gc=$(kubectl get gatewayclass eg -o jsonpath='{.spec.controllerName}' 2>/dev/null || echo "")
if [[ "$gc" == "gateway.envoyproxy.io/gatewayclass-controller" ]]; then
  pass "GatewayClass eg exists with controller=$gc"
else
  fail "GatewayClass eg missing or wrong controller: $gc"
fi

step "Gateway 'apollo-gateway' is Programmed"
prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$prog" == "True" ]]; then
  pass "apollo-gateway is Programmed"
else
  fail "apollo-gateway is not Programmed (status=$prog)"
fi

step "HTTPRoutes (6 expected, all with parent status)"
rt_count=$(kubectl get httproute -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
parent_count=$(kubectl get httproute -A -o custom-columns="P:.status.parents[*].controllerName" --no-headers 2>/dev/null | grep -c "gateway.envoyproxy.io" || echo 0)
if [[ "$rt_count" -ge 6 ]] && [[ "$parent_count" -ge 6 ]]; then
  pass "$rt_count HTTPRoutes, all $parent_count have parents"
else
  fail "only $rt_count/$parent_count HTTPRoutes have parents"
fi

step "Port-forward check (port $PORT)"
PORT_FORWARD_HINT="kubectl port-forward -n envoy-gateway-system svc/\$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}') ${PORT}:80"
# Try a quick curl to check if anything is listening on the port
if curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://localhost:${PORT}/" 2>/dev/null | grep -qE "^[0-9]+$"; then
  pass "port-forward appears active on localhost:$PORT"
else
  fail "No port-forward on localhost:$PORT — start one first:
        $PORT_FORWARD_HINT"
  echo ""
  echo "Skipping remaining smoke tests (need port-forward)."
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

step "Smoke test: Envoy → identity (Host header, /healthz)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "$ENTRY/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Envoy → identity → 200"
else
  fail "Envoy → identity → $RESP (expected 200)"
fi

step "Smoke test: Envoy → flight (Host header, /api/flights)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "$ENTRY/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Envoy → flight → 200"
else
  fail "Envoy → flight → $RESP (expected 200)"
fi

step "Smoke test: Envoy → frontend (Host header)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "$ENTRY/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Envoy → frontend → 200"
else
  fail "Envoy → frontend → $RESP (expected 200)"
fi

step "Smoke test: full login flow through Envoy Gateway"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "$ENTRY/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through Envoy returned a JWT (${#TOKEN} chars)"
else
  fail "Login through Envoy failed: $LOGIN_RESP"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
