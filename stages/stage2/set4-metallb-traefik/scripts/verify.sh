#!/bin/bash
# Verify Set 4: Traefik Ingress (host-based, LoadBalancer IP via MetalLB L2).
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

step "Namespaces (3 expected: apps, ui, metallb-system)"
for ns in apollo-airlines-apps apollo-airlines-ui metallb-system; do
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
    fail "deploy $ns/$name not ready (ready=$ready)"
  fi
done

step "MetalLB controller"
if kubectl get deploy controller -n metallb-system >/dev/null 2>&1; then
  ready=$(kubectl get deploy controller -n metallb-system -o jsonpath='{.status.readyReplicas}')
  if [[ "$ready" -ge 1 ]]; then
    pass "metallb controller ready=$ready"
  else
    fail "metallb controller not ready"
  fi
else
  fail "metallb controller missing"
fi

step "Traefik DaemonSet"
if kubectl get ds traefik -n kube-system >/dev/null 2>&1; then
  ready=$(kubectl get ds traefik -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 1 ]]; then
    pass "traefik DS ready=$ready"
  else
    fail "traefik DS not ready"
  fi
else
  fail "traefik DS not found"
fi

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

step "Traefik LoadBalancer Service has an IP from MetalLB"
LB_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$LB_IP" ]]; then
  pass "MetalLB assigned IP: $LB_IP"
else
  fail "no LoadBalancer IP assigned to traefik"
  echo "Skipping smoke tests (no MetalLB IP)."
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

step "IngressClass 'traefik'"
if kubectl get ingressclass traefik >/dev/null 2>&1; then
  pass "ingressclass traefik exists"
else
  fail "ingressclass traefik missing"
fi

step "Ingress resources (5 expected)"
ing_count=$(kubectl get ingress -A --no-headers 2>/dev/null | grep -c apollo-airlines | head -1)
if [[ "$ing_count" -ge 5 ]]; then pass "$ing_count Ingress resources"; else fail "only $ing_count Ingress resources"; fi

# Skip smoke tests if no IP
if [[ -z "$LB_IP" ]]; then
  echo ""
  echo "Skipping smoke tests (no MetalLB IP)."
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

step "Smoke test: Traefik → identity (Host header, /healthz) at $LB_IP"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "http://$LB_IP/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → identity → 200"
else
  fail "Traefik → identity → $RESP (expected 200)"
fi

step "Smoke test: Traefik → flight (Host header, /api/flights)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "http://$LB_IP/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → flight → 200"
else
  fail "Traefik → flight → $RESP (expected 200)"
fi

step "Smoke test: Traefik → frontend (Host header)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://$LB_IP/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → frontend → 200"
else
  fail "Traefik → frontend → $RESP (expected 200)"
fi

step "Smoke test: full login flow through Traefik"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "http://$LB_IP/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through Traefik returned a JWT (${#TOKEN} chars)"
else
  fail "Login through Traefik failed: $LOGIN_RESP"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
