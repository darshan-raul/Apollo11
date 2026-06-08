#!/bin/bash
# Verify Set 1: runs a battery of checks against the cluster.
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

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
for j in init-identity-db init-flight-db init-booking-db; do
  s=$(kubectl get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then pass "job $j succeeded"; else fail "job $j succeeded=$s"; fi
done

step "Services (10 normal + 4 headless)"
total_svc=$(kubectl get svc -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
if [[ "$total_svc" -ge 14 ]]; then pass "$total_svc services total"; else fail "only $total_svc services (expected 14+)"; fi
for s in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
  if kubectl get svc "$s" -n apollo-airlines-apps >/dev/null 2>&1; then
    pass "headless svc $s exists"
  else
    fail "headless svc $s missing"
  fi
done

step "NetworkPolicies (NOT auto-applied — see apply.sh)"
np_count=$(kubectl get netpol -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
echo "  $np_count NetworkPolicies active in cluster (manifests exist under k8s/networkpolicies/ for reference)"

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

step "Smoke test: search"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:30084/api/search?origin=BOM&destination=SIN" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "GET /api/search → 200"
else
  fail "GET /api/search → $RESP (expected 200)"
fi

step "Smoke test: frontend"
RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:30080 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then
  pass "GET / → 200 (frontend)"
else
  fail "GET / → $RESP (expected 200)"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
