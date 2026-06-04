#!/bin/bash
# Apollo11 — Stage 2 Self-Check Script
# Verifies all services deployed across 3 namespaces with DNS, NetworkPolicies,
# Ingress, Gateway API, and ServiceAccounts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACES="apollo-airlines-infra apollo-airlines-apps apollo-airlines-ui"
PASS=0; FAIL=0

info()  { echo -e "  \033[1;34m[INFO]\033[0m  $1"; }
pass()  { echo -e "  \033[1;32m[PASS]\033[0m  $1"; ((PASS++)); }
fail()  { echo -e "  \033[1;31m[FAIL]\033[0m  $1"; ((FAIL++)); }
warn()  { echo -e "  \033[1;33m[WARN]\033[0m  $1"; }

section() { echo ""; echo -e "\033[1;36m=== $1 ===\033[0m"; }

# ── Section 1: Namespaces ────────────────────────────────────────────────
section "1. Namespaces exist"
for ns in $NAMESPACES; do
  if kubectl get namespace "$ns" &>/dev/null; then
    pass "$ns namespace exists"
  else
    fail "$ns namespace NOT found"
  fi
done

# ── Section 2: ServiceAccounts ─────────────────────────────────────────────
section "2. ServiceAccounts exist"
for ns in $NAMESPACES; do
  sa_name="${ns#apollo-airlines-}"  # infra, apps, ui
  sa_name="apollo11-${sa_name}"
  if kubectl get sa "$sa_name" -n "$ns" &>/dev/null; then
    pass "$ns: ServiceAccount '$sa_name' exists"
  else
    fail "$ns: ServiceAccount '$sa_name' NOT found"
  fi
done

# ── Section 3: ConfigMap and Secrets ─────────────────────────────────────
section "3. ConfigMap and Secrets in apollo-airlines-apps"
if kubectl get configmap apollo-airlines-config -n apollo-airlines-apps &>/dev/null; then
  pass "apollo-airlines-config ConfigMap exists"
  if kubectl get configmap apollo-airlines-config -n apollo-airlines-apps -o jsonpath='{.data.IDENTITY_SERVICE_URL}' | grep -q "svc.cluster.local"; then
    pass "Service URLs use FQDN format"
  else
    fail "Service URLs missing FQDN format"
  fi
else
  fail "apollo-airlines-config ConfigMap NOT found"
fi

if kubectl get secret apollo-airlines-secrets -n apollo-airlines-apps &>/dev/null; then
  pass "apollo-airlines-secrets Secret exists"
else
  fail "apollo-airlines-secrets Secret NOT found"
fi

# ── Section 4: Ingress and Gateway ─────────────────────────────────────────
section "4. Ingress and Gateway API resources"
if kubectl get ingress apollo-airlines-gateway -n apollo-airlines-ui &>/dev/null; then
  pass "Ingress 'apollo-airlines-gateway' exists in apollo-airlines-ui"
else
  fail "Ingress 'apollo-airlines-gateway' NOT found"
fi

if kubectl get gateway gateway -n apollo-airlines-apps &>/dev/null; then
  pass "Gateway 'gateway' exists in apollo-airlines-apps"
else
  fail "Gateway 'gateway' NOT found"
fi

# ── Section 5: Infrastructure Deployments ──────────────────────────────────
section "5. Infrastructure Deployments (infra namespace)"
for dep in identity-db flight-db booking-db redis; do
  if kubectl get deployment "$dep" -n apollo-airlines-infra &>/dev/null; then
    pass "infra/$dep Deployment exists"
  else
    fail "infra/$dep Deployment NOT found"
  fi
done

# ── Section 6: App Deployments ────────────────────────────────────────────
section "6. Application Deployments (apps namespace)"
for dep in identity flight booking search notification; do
  if kubectl get deployment "$dep" -n apollo-airlines-apps &>/dev/null; then
    pass "apps/$dep Deployment exists"
  else
    fail "apps/$dep Deployment NOT found"
  fi
done

# ── Section 7: UI Deployment ─────────────────────────────────────────────
section "7. Frontend Deployment (ui namespace)"
if kubectl get deployment frontend -n apollo-airlines-ui &>/dev/null; then
  pass "ui/frontend Deployment exists"
else
  fail "ui/frontend Deployment NOT found"
fi

# ── Section 8: Deployment ReadyReplicas ───────────────────────────────────
section "8. Deployment ReadyReplicas"
for ns in $NAMESPACES; do
  deploys=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  for dep in $deploys; do
    replicas=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$replicas" == "1" ]] || [[ "$replicas" == "2" ]]; then
      pass "$ns/$dep: readyReplicas=$replicas"
    elif [[ -z "$replicas" ]]; then
      fail "$ns/$dep: readyReplicas=0 (not ready)"
    else
      warn "$ns/$dep: readyReplicas=$replicas"
    fi
  done
done

# ── Section 9: Services ─────────────────────────────────────────────────────
section "9. Services exist with correct ports"
declare -A SERVICES
SERVICES=(
  ["identity-db"]="5432"
  ["flight-db"]="5432"
  ["booking-db"]="5432"
  ["redis"]="6379"
  ["identity"]="8080"
  ["flight"]="8081"
  ["booking"]="8082"
  ["search"]="8083"
  ["notification"]="8084"
  ["frontend"]="3000"
)
for svc in "${!SERVICES[@]}"; do
  port="${SERVICES[$svc]}"
  case "$svc" in
    identity-db|flight-db|booking-db|redis) ns="apollo-airlines-infra" ;;
    frontend) ns="apollo-airlines-ui" ;;
    *) ns="apollo-airlines-apps" ;;
  esac
  actual=$(kubectl get svc "$svc" -n "$ns" -o jsonpath="{.spec.ports[?(@.port==$port)].port}" 2>/dev/null || echo "")
  if [[ "$actual" == "$port" ]]; then
    pass "$svc:$port Service exists"
  else
    fail "$svc: expected port $port, found '$actual'"
  fi
done

# ── Section 10: NetworkPolicies ────────────────────────────────────────────
section "10. NetworkPolicies exist"
for entry in \
  "identity-db-allow-apps:apollo-airlines-infra" \
  "flight-db-allow-apps:apollo-airlines-infra" \
  "booking-db-allow-apps:apollo-airlines-infra" \
  "redis-allow-apps:apollo-airlines-infra" \
  "identity-allow-specific:apollo-airlines-apps" \
  "flight-allow-specific:apollo-airlines-apps" \
  "booking-allow-specific:apollo-airlines-apps" \
  "search-allow-specific:apollo-airlines-apps" \
  "notification-allow-specific:apollo-airlines-apps" \
  "frontend-allow-external:apollo-airlines-ui"; do
  IFS=':' read -r name ns <<< "$entry"
  if kubectl get netpol "$name" -n "$ns" &>/dev/null; then
    pass "NetworkPolicy $ns/$name exists"
  else
    fail "NetworkPolicy $ns/$name NOT found"
  fi
done

# ── Section 11: Init Jobs ───────────────────────────────────────────────────
section "11. Init Jobs completed"
for job in init-identity-db init-flight-db init-booking-db; do
  if kubectl get job "$job" -n apollo-airlines-apps &>/dev/null; then
    pass "Job '$job' exists"
    succeeded=$(kubectl get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$succeeded" == "1" ]]; then
      pass "Job '$job' completed successfully"
    else
      fail "Job '$job' has not completed (succeeded=$succeeded)"
    fi
  else
    fail "Job '$job' NOT found"
  fi
done

# ── Section 12: serviceAccountName ─────────────────────────────────────────
section "12. serviceAccountName on all Deployments"
all_deps=(
  "identity:apollo-airlines-apps"
  "flight:apollo-airlines-apps"
  "booking:apollo-airlines-apps"
  "search:apollo-airlines-apps"
  "notification:apollo-airlines-apps"
  "frontend:apollo-airlines-ui"
  "identity-db:apollo-airlines-infra"
  "flight-db:apollo-airlines-infra"
  "booking-db:apollo-airlines-infra"
  "redis:apollo-airlines-infra"
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

# ── Section 13: Headless Services ──────────────────────────────────────────
section "13. Headless Services (clusterIP: None)"
for svc in identity-db flight-db booking-db redis; do
  ip=$(kubectl get svc "$svc" -n apollo-airlines-infra -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ "$ip" == "None" ]]; then
    pass "$svc is Headless (clusterIP=None)"
  else
    fail "$svc clusterIP=$ip (expected None for Headless)"
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
  exit 1
fi

echo ""
echo "All checks passed. Stage 2 is fully deployed."
echo ""
echo "Next: bash test/stage2_test.sh (this script)"
echo "Then: cd stages/stage2 && kubectl apply -k k8s/"
exit 0