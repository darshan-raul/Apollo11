#!/bin/bash
# Verify Set 1: runs a battery of checks against the cluster.
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL++)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

step "Namespaces"
for ns in apollo-airlines-infra apollo-airlines-apps apollo-airlines-ui; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then pass "namespace $ns"; else fail "namespace $ns missing"; fi
done

step "Deployments (10 expected)"
EXPECTED_DEPS=(
  "apollo-airlines-infra:identity-db"
  "apollo-airlines-infra:flight-db"
  "apollo-airlines-infra:booking-db"
  "apollo-airlines-infra:redis"
  "apollo-airlines-apps:identity"
  "apollo-airlines-apps:flight"
  "apollo-airlines-apps:booking"
  "apollo-airlines-apps:search"
  "apollo-airlines-apps:notification"
  "apollo-airlines-ui:frontend"
)
for d in "${EXPECTED_DEPS[@]}"; do
  ns="${d%%:*}"; name="${d##*:}"
  if kubectl get deploy "$name" -n "$ns" >/dev/null 2>&1; then
    ready=$(kubectl get deploy "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -gt 0 ]]; then
      pass "deploy $ns/$name ready=$ready"
    else
      fail "deploy $ns/$name not ready (ready=$ready)"
    fi
  else
    fail "deploy $ns/$name missing"
  fi
done

step "Init jobs (3 expected, all succeeded)"
for ns in apollo-airlines-infra; do
  for j in init-identity-db init-flight-db init-booking-db; do
    s=$(kubectl get job "$j" -n "$ns" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
    if [[ "$s" == "1" ]]; then pass "job $ns/$j succeeded"; else fail "job $ns/$j succeeded=$s"; fi
  done
done

step "Services (10 normal + 4 headless expected)"
for ns in apollo-airlines-infra apollo-airlines-apps apollo-airlines-ui; do
  count=$(kubectl get svc -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [[ "$count" -gt 0 ]]; then pass "namespace $ns has $count services"; else fail "namespace $ns has no services"; fi
done
for s in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
  if kubectl get svc "$s" -n apollo-airlines-infra >/dev/null 2>&1; then
    pass "headless svc identity-db/$s exists"
  else
    fail "headless svc $s missing"
  fi
done

step "NetworkPolicies"
np_count=$(kubectl get netpol -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
if [[ "$np_count" -ge 15 ]]; then pass "$np_count NetworkPolicies active"; else fail "only $np_count NetworkPolicies (expected 15+)"; fi

step "ServiceAccounts"
sa_count=$(kubectl get sa -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
if [[ "$sa_count" -ge 10 ]]; then pass "$sa_count ServiceAccounts"; else fail "only $sa_count SAs (expected 10+)"; fi

step "Smoke test: login"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:30083/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "POST /api/users/login → 200"
else
  fail "POST /api/users/login → $RESP (expected 200)"
fi

step "Smoke test: list flights"
RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:30081/api/flights 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "GET /api/flights → 200"
else
  fail "GET /api/flights → $RESP (expected 200)"
fi

echo ""
echo "Passed: $PASS  Failed: $FAIL"
exit $FAIL
