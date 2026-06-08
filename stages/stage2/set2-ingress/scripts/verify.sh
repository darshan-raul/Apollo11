#!/bin/bash
# Verify Set 2: Traefik Ingress routes by Host header.
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

ENTRY="http://localhost:30443"

step "Namespaces (2 expected)"
for ns in apollo-airlines-apps apollo-airlines-ui; do
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

step "Init jobs (3 expected, all succeeded)"
for j in init-identity-db init-flight-db init-booking-db; do
  s=$(kubectl get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then pass "job $j succeeded"; else fail "job $j succeeded=$s"; fi
done

step "Services (all ClusterIP)"
total_svc=$(kubectl get svc -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
if [[ "$total_svc" -ge 14 ]]; then pass "$total_svc services total"; else fail "only $total_svc services"; fi
np_count=$(kubectl get svc -A --no-headers 2>/dev/null | grep apollo-airlines | grep -c NodePort || true)
if [[ "$np_count" == "0" ]]; then pass "no NodePort services (all ClusterIP)"; else fail "$np_count NodePort services still present"; fi

step "Traefik DaemonSet"
if kubectl get ds traefik -n kube-system >/dev/null 2>&1; then
  ready=$(kubectl get ds traefik -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 1 ]]; then
    pass "traefik DS ready=$ready"
  else
    fail "traefik DS not ready (ready=$ready)"
  fi
else
  fail "traefik DS not found"
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

step "Smoke test: Traefik reaches identity (Host header, /healthz)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "$ENTRY/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → identity → 200"
else
  fail "Traefik → identity → $RESP (expected 200)"
fi

step "Smoke test: Traefik reaches flight (Host header, /api/flights)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "$ENTRY/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → flight → 200"
else
  fail "Traefik → flight → $RESP (expected 200)"
fi

step "Smoke test: Traefik reaches frontend (Host header)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "$ENTRY/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "Traefik → frontend → 200"
else
  fail "Traefik → frontend → $RESP (expected 200)"
fi

step "Smoke test: Traefik returns 404 for unknown host"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: nope.apollo.local" "$ENTRY/" 2>/dev/null || echo "000")
if [[ "$RESP" == "404" ]]; then
  pass "Traefik returns 404 for unknown host"
else
  fail "Traefik returns $RESP for unknown host (expected 404)"
fi

step "Smoke test: full login flow through Traefik"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "$ENTRY/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through Traefik returned a JWT (${#TOKEN} chars)"
else
  fail "Login through Traefik failed: $LOGIN_RESP"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
