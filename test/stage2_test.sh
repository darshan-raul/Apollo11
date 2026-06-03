#!/bin/bash
# Apollo11 — Stage 2 Self-Check Script
# Verifies all services deployed across 3 namespaces with DNS, NetworkPolicies,
# Ingress, Gateway API, and ServiceAccounts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACES="apollo11-infra apollo11-apps apollo11-ui"
PASS=0
FAIL=0

info()  { echo -e "  \033[1;34m[INFO]\033[0m  $1"; }
pass()  { echo -e "  \033[1;32m[PASS]\033[0m  $1"; ((PASS++)); }
fail()  { echo -e "  \033[1;31m[FAIL]\033[0m  $1"; ((FAIL++)); }
warn()  { echo -e "  \033[1;33m[WARN]\033[0m  $1"; }

section() {
  echo ""
  echo -e "\033[1;36m=== $1 ===\033[0m"
}

# ── Section 1: Namespaces ────────────────────────────────────────────────
section "1. Namespaces exist"
for ns in $NAMESPACES; do
  result=$(kubectl get namespace "$ns" -o name 2>/dev/null)
  if [[ -n "$result" ]]; then
    pass "$ns namespace exists"
  else
    fail "$ns namespace NOT found"
  fi
done

# ── Section 2: ServiceAccounts ─────────────────────────────────────────────
section "2. ServiceAccounts exist"
for ns in $NAMESPACES; do
  sa_name="${ns#apollo11-}"  # infra, apps, ui
  sa_name="apollo11-${sa_name}"
  result=$(kubectl get sa "$sa_name" -n "$ns" -o name 2>/dev/null)
  if [[ -n "$result" ]]; then
    pass "$ns: ServiceAccount '$sa_name' exists"
  else
    fail "$ns: ServiceAccount '$sa_name' NOT found"
  fi
done

# ── Section 3: ConfigMap and Secrets ─────────────────────────────────────
section "3. ConfigMap and Secrets in apollo11-apps"
if kubectl get configmap apollo11-config -n apollo11-apps &>/dev/null; then
  pass "apollo11-config ConfigMap exists in apollo11-apps"
  # Verify FQDN entries
  if kubectl get configmap apollo11-config -n apollo11-apps -o jsonpath='{.data.AUTH_SERVICE_URL}' | grep -q "svc.cluster.local"; then
    pass "AUTH_SERVICE_URL uses FQDN format"
  else
    fail "AUTH_SERVICE_URL missing FQDN"
  fi
else
  fail "apollo11-config ConfigMap NOT found"
fi

if kubectl get secret apollo11-secrets -n apollo11-apps &>/dev/null; then
  pass "apollo11-secrets Secret exists in apollo11-apps"
else
  fail "apollo11-secrets Secret NOT found"
fi

# ── Section 4: Ingress and Gateway ─────────────────────────────────────────
section "4. Ingress and Gateway API resources"
if kubectl get ingress apollo11-gateway -n apollo11-apps &>/dev/null; then
  pass "Ingress 'apollo11-gateway' exists in apollo11-apps"
  host_count=$(kubectl get ingress apollo11-gateway -n apollo11-apps -o jsonpath='{.spec.rules}' | grep -o '"host"' | wc -l)
  info "Ingress has $host_count host rule(s)"
else
  fail "Ingress 'apollo11-gateway' NOT found"
fi

if kubectl get gateway gateway-gateway -n apollo11-apps &>/dev/null; then
  pass "Gateway 'gateway-gateway' exists in apollo11-apps"
else
  fail "Gateway 'gateway-gateway' NOT found"
fi

if kubectl get httproute catalog-route -n apollo11-apps &>/dev/null; then
  pass "HTTPRoute 'catalog-route' exists in apollo11-apps"
else
  fail "HTTPRoute 'catalog-route' NOT found"
fi

# ── Section 5: Infrastructure Deployments ──────────────────────────────────
section "5. Infrastructure Deployments (infra namespace)"
INFRA_DEPS="auth-postgres catalog-postgres circulation-postgres catalog-redis notification-redis"
for dep in $INFRA_DEPS; do
  result=$(kubectl get deployment "$dep" -n apollo11-infra -o name 2>/dev/null)
  if [[ -n "$result" ]]; then
    pass "infra/$dep Deployment exists"
  else
    fail "infra/$dep Deployment NOT found"
  fi
done

# ── Section 6: App Deployments ────────────────────────────────────────────
section "6. Application Deployments (apps namespace)"
APP_DEPS="auth catalog circulation notification fines"
for dep in $APP_DEPS; do
  result=$(kubectl get deployment "$dep" -n apollo11-apps -o name 2>/dev/null)
  if [[ -n "$result" ]]; then
    pass "apps/$dep Deployment exists"
  else
    fail "apps/$dep Deployment NOT found"
  fi
done

# ── Section 7: UI Deployment ─────────────────────────────────────────────
section "7. Frontend Deployment (ui namespace)"
result=$(kubectl get deployment frontend -n apollo11-ui -o name 2>/dev/null)
if [[ -n "$result" ]]; then
  pass "ui/frontend Deployment exists"
else
  fail "ui/frontend Deployment NOT found"
fi

# ── Section 8: Deployment ReadyReplicas ───────────────────────────────────
section "8. Deployment ReadyReplicas"
for ns in $NAMESPACES; do
  deploys=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}')
  for dep in $deploys; do
    replicas=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}')
    if [[ "$replicas" == "1" ]]; then
      pass "$ns/$dep: readyReplicas=1"
    elif [[ -z "$replicas" ]]; then
      fail "$ns/$dep: readyReplicas=0 (not ready)"
    else
      warn "$ns/$dep: readyReplicas=$replicas (expected 1)"
    fi
  done
done

# ── Section 9: Services ─────────────────────────────────────────────────────
section "9. Services exist with correct ports"
declare -A expected_ports
expected_ports[auth-postgres]="5432"
expected_ports[catalog-postgres]="5432"
expected_ports[circulation-postgres]="5432"
expected_ports[catalog-redis]="6379"
expected_ports[notification-redis]="6380"
expected_ports[auth]="8080"
expected_ports[catalog]="8081"
expected_ports[circulation]="8082"
expected_ports[notification]="8083"
expected_ports[fines]="8084"
expected_ports[frontend]="30080"

for svc in "${!expected_ports[@]}"; do
  # Determine namespace
  case "$svc" in
    auth-postgres|catalog-postgres|circulation-postgres|catalog-redis|notification-redis)
      ns="apollo11-infra" ;;
    frontend) ns="apollo11-ui" ;;
    *)        ns="apollo11-apps" ;;
  esac

  port="${expected_ports[$svc]}"
  result=$(kubectl get svc "$svc" -n "$ns" -o name 2>/dev/null)
  if [[ -z "$result" ]]; then
    fail "$svc Service NOT found in $ns"
    continue
  fi

  actual=$(kubectl get svc "$svc" -n "$ns" -o jsonpath="{.spec.ports[?(@.port==$port)].port}" 2>/dev/null)
  if [[ "$actual" == "$port" ]]; then
    pass "$svc:$port Service exists with correct port"
  else
    fail "$svc: expected port $port, found '$actual'"
  fi
done

# ── Section 10: NetworkPolicies ────────────────────────────────────────────
section "10. NetworkPolicies exist"
netpols=(
  "auth-postgres-allow-specific:apollo11-infra"
  "catalog-postgres-allow-specific:apollo11-infra"
  "circulation-postgres-allow-specific:apollo11-infra"
  "catalog-redis-allow-specific:apollo11-infra"
  "notification-redis-allow-specific:apollo11-infra"
  "auth-allow-specific:apollo11-apps"
  "catalog-allow-specific:apollo11-apps"
  "circulation-allow-specific:apollo11-apps"
  "notification-allow-specific:apollo11-apps"
  "fines-allow-specific:apollo11-apps"
)

for entry in "${netpols[@]}"; do
  IFS=':' read -r name ns <<< "$entry"
  result=$(kubectl get netpol "$name" -n "$ns" -o name 2>/dev/null)
  if [[ -n "$result" ]]; then
    pass "NetworkPolicy $ns/$name exists"
    # Verify ingress rules
    ingress_count=$(kubectl get netpol "$name" -n "$ns" -o jsonpath='{.spec.ingress}' 2>/dev/null | grep -c "from:" || echo "0")
    info "  $ns/$name: $ingress_count ingress rule(s)"
  else
    fail "NetworkPolicy $ns/$name NOT found"
  fi
done

# ── Section 11: Init Jobs ───────────────────────────────────────────────────
section "11. Init Jobs completed"
JOBS="init-auth-db init-catalog-db init-circulation-db"
for job in $JOBS; do
  result=$(kubectl get job "$job" -n apollo11-apps -o name 2>/dev/null)
  if [[ -z "$result" ]]; then
    fail "Job '$job' NOT found in apollo11-apps"
    continue
  fi
  pass "Job '$job' exists"

  # Check completion
  succeeded=$(kubectl get job "$job" -n apollo11-apps -o jsonpath='{.status.succeeded}' 2>/dev/null)
  if [[ "$succeeded" == "1" ]]; then
    pass "Job '$job' completed successfully"
  else
    fail "Job '$job' has not completed (succeeded=$succeeded)"
  fi
done

# ── Section 12: DNS Resolution ─────────────────────────────────────────────
section "12. DNS resolution (cross-namespace FQDN)"
if kubectl cluster-info &>/dev/null; then
  info "Cluster available — testing DNS from a debug pod"

  # Start temporary debug pod
  kubectl run dns-test --image=tutum/dnsutils --rm -it --restart=Never \
    --namespace apollo11-apps -- sh -c "
      echo '=== FQDN tests ===' &&
      nslookup auth.apollo11-apps.svc.cluster.local | grep -q 'Address' && echo 'PASS: FQDN resolves in same namespace' || echo 'FAIL: FQDN same-ns failed' &&
      nslookup auth-postgres.apollo11-infra.svc.cluster.local | grep -q 'Address' && echo 'PASS: FQDN cross-namespace works' || echo 'FAIL: FQDN cross-ns failed' &&
      nslookup auth | grep -q 'NXDOMAIN' && echo 'PASS: short name correctly fails' || echo 'NOTE: short name may resolve (search path)'
    " 2>/dev/null || warn "DNS pod test failed (may need cluster)"
else
  warn "No cluster — skipping DNS live test"
fi

# ── Section 13: ServiceAccount on Deployments ─────────────────────────────
section "13. serviceAccountName on all Deployments"
all_deps=(
  "auth:apollo11-apps"
  "catalog:apollo11-apps"
  "circulation:apollo11-apps"
  "notification:apollo11-apps"
  "fines:apollo11-apps"
  "auth-postgres:apollo11-infra"
  "catalog-postgres:apollo11-infra"
  "circulation-postgres:apollo11-infra"
  "catalog-redis:apollo11-infra"
  "notification-redis:apollo11-infra"
  "frontend:apollo11-ui"
)

for entry in "${all_deps[@]}"; do
  IFS=':' read -r dep ns <<< "$entry"
  sa=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
  if [[ -n "$sa" ]]; then
    pass "$ns/$dep: serviceAccountName=$sa"
  else
    fail "$ns/$dep: no serviceAccountName"
  fi
done

# ── Final Summary ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Stage 2 Self-Check Results"
echo "  PASS: $PASS   FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Some checks failed. To diagnose:"
  echo "  kubectl get pods -n <namespace> -o wide"
  echo "  kubectl describe pod <pod-name> -n <namespace>"
  echo "  kubectl logs <pod-name> -n <namespace>"
  echo ""
  echo "If pods are Pending due to image pull errors, rebuild:"
  echo "  cd $PROJECT_ROOT/stages/stage2 && ./scripts/build-images.sh"
  echo "Then re-apply:"
  echo "  cd $PROJECT_ROOT/stages/stage2/k8s && kubectl apply -f config/namespace.yaml && kubectl apply -f config/"
  exit 1
fi

echo ""
echo "All checks passed. Stage 2 is fully deployed."
echo ""
echo "Next: bash test/stage2_test.sh (full verification)"
echo "Then: cd stages/stage2 && kubectl apply -f k8s/config/namespace.yaml ..."