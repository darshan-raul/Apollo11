#!/bin/bash
# stage3_test.sh — verify Stage 3 StatefulSet + PVC + Headless setup
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
    local label="$1"; local cmd="$2"
    echo -n "[$label] "
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"; ((PASS++)); return 0
    else
        echo -e "${RED}FAIL${NC} — $cmd"; ((FAIL++)); return 1
    fi
}

check_raw() {
    local label="$1"; local cmd="$2"
    echo -n "[$label] "
    local output
    output=$(eval "$cmd" 2>&1) || true
    if [[ -n "$output" ]]; then
        echo -e "${GREEN}PASS${NC} — $output"; ((PASS++)); return 0
    else
        echo -e "${RED}FAIL${NC}"; ((FAIL++)); return 1
    fi
}

echo "============================================"
echo "  Apollo11 Stage 3 — StatefulSet Verification"
echo "============================================"
echo ""

# --- Namespaces ---
echo "--- Namespaces ---"
check "apollo11-infra exists" "kubectl get ns apollo11-infra"
check "apollo11-apps exists" "kubectl get ns apollo11-apps"
check "apollo11-ui exists" "kubectl get ns apollo11-ui"
echo ""

# --- StatefulSets (6 total: 3 postgres + 2 redis + 1 fines) ---
echo "--- StatefulSets ---"
check "auth-postgres StatefulSet" "kubectl get sts auth-postgres -n apollo11-infra"
check "catalog-postgres StatefulSet" "kubectl get sts catalog-postgres -n apollo11-infra"
check "circulation-postgres StatefulSet" "kubectl get sts circulation-postgres -n apollo11-infra"
check "catalog-redis StatefulSet" "kubectl get sts catalog-redis -n apollo11-infra"
check "notification-redis StatefulSet" "kubectl get sts notification-redis -n apollo11-infra"
check "fines StatefulSet" "kubectl get sts fines -n apollo11-apps"
echo ""

# --- PersistentVolumeClaims (1 per pod) ---
echo "--- PersistentVolumeClaims (1 per pod) ---"
check "auth-postgres PVC bound" "kubectl get pvc -n apollo11-infra -l app=auth-postgres"
check "catalog-postgres PVC bound" "kubectl get pvc -n apollo11-infra -l app=catalog-postgres"
check "circulation-postgres PVC bound" "kubectl get pvc -n apollo11-infra -l app=circulation-postgres"
check "catalog-redis PVC bound" "kubectl get pvc -n apollo11-infra -l app=catalog-redis"
check "notification-redis PVC bound" "kubectl get pvc -n apollo11-infra -l app=notification-redis"
check "fines PVC bound" "kubectl get pvc -n apollo11-apps -l app=fines"
echo ""

# --- Headless Services (clusterIP: None) ---
echo "--- Headless Services (clusterIP: None) ---"
check_raw "auth-postgres-headless clusterIP=None" \
    "kubectl get svc auth-postgres-headless -n apollo11-infra -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
check_raw "catalog-postgres-headless clusterIP=None" \
    "kubectl get svc catalog-postgres-headless -n apollo11-infra -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
check_raw "circulation-postgres-headless clusterIP=None" \
    "kubectl get svc circulation-postgres-headless -n apollo11-infra -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
check_raw "catalog-redis-headless clusterIP=None" \
    "kubectl get svc catalog-redis-headless -n apollo11-infra -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
check_raw "notification-redis-headless clusterIP=None" \
    "kubectl get svc notification-redis-headless -n apollo11-infra -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
check_raw "fines-headless clusterIP=None" \
    "kubectl get svc fines-headless -n apollo11-apps -o jsonpath='{.spec.clusterIP}' | grep -q '^None$'"
echo ""

# --- Init Containers (postgres StatefulSets) ---
echo "--- Init Containers (postgres StatefulSets) ---"
check "auth-postgres init container" \
    "kubectl get pod -n apollo11-infra -l app=auth-postgres -o jsonpath='{.items[0].spec.initContainers[0].name}' | grep -q init"
check "catalog-postgres init container" \
    "kubectl get pod -n apollo11-infra -l app=catalog-postgres -o jsonpath='{.items[0].spec.initContainers[0].name}' | grep -q init"
check "circulation-postgres init container" \
    "kubectl get pod -n apollo11-infra -l app=circulation-postgres -o jsonpath='{.items[0].spec.initContainers[0].name}' | grep -q init"

# Init containers must have terminated with exit 0
check "auth-postgres init terminated (exit 0)" \
    "kubectl get pod -n apollo11-infra -l app=auth-postgres -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}' | grep -q '^0$'"
check "catalog-postgres init terminated (exit 0)" \
    "kubectl get pod -n apollo11-infra -l app=catalog-postgres -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}' | grep -q '^0$'"
check "circulation-postgres init terminated (exit 0)" \
    "kubectl get pod -n apollo11-infra -l app=circulation-postgres -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}' | grep -q '^0$'"
echo ""

# --- Init ConfigMaps ---
echo "--- Init ConfigMaps ---"
check "auth-postgres-init-script ConfigMap" "kubectl get cm auth-postgres-init-script -n apollo11-infra"
check "catalog-postgres-init-script ConfigMap" "kubectl get cm catalog-postgres-init-script -n apollo11-infra"
check "circulation-postgres-init-script ConfigMap" "kubectl get cm circulation-postgres-init-script -n apollo11-infra"
echo ""

# --- Frontend (NodePort → Ingress) ---
echo "--- Frontend (Ingress replaces NodePort) ---"
check "frontend Ingress exists" "kubectl get ingress frontend -n apollo11-ui"
check_raw "frontend Ingress host" \
    "kubectl get ingress frontend -n apollo11-ui -o jsonpath='{.spec.rules[0].host}' | grep -q 'frontend.apollo11.local'"
check "frontend Service is ClusterIP (not NodePort)" \
    "[[ \$(kubectl get svc frontend -n apollo11-ui -o jsonpath='{.spec.type}') == ClusterIP ]]"
echo ""

# --- App Deployments (unchanged from stage2) ---
echo "--- App Deployments (unchanged) ---"
check "auth Deployment" "kubectl get deploy auth -n apollo11-apps"
check "catalog Deployment" "kubectl get deploy catalog -n apollo11-apps"
check "circulation Deployment" "kubectl get deploy circulation -n apollo11-apps"
check "notification Deployment" "kubectl get deploy notification -n apollo11-apps"
check "frontend Deployment" "kubectl get deploy frontend -n apollo11-ui"
echo ""

# --- Replica counts ---
echo "--- Replica Counts ---"
for svc in auth catalog circulation notification; do
    check_raw "$svc replicas=2" \
        "kubectl get deploy $svc -n apollo11-apps -o jsonpath='{.spec.replicas}' | grep -q '^2\$'"
done
check_raw "frontend replicas=2" \
    "kubectl get deploy frontend -n apollo11-ui -o jsonpath='{.spec.replicas}' | grep -q '^2\$'"
echo ""

# --- Init Jobs (still run once after cluster setup) ---
echo "--- Init Jobs ---"
for job in init-auth-db init-catalog-db init-circulation-db; do
    check "$job completed (1/1)" "kubectl get job $job -n apollo11-apps | grep -q '1/1'"
done
echo ""

# --- NetworkPolicies ---
echo "--- NetworkPolicies ---"
for netpol in auth catalog circulation notification fines; do
    check "$netpol NetworkPolicy" "kubectl get netpol $netpol -n apollo11-apps"
done
for netpol in auth-postgres catalog-postgres circulation-postgres catalog-redis notification-redis; do
    check "$netpol NetworkPolicy" "kubectl get netpol $netpol -n apollo11-infra"
done
echo ""

# --- serviceAccountName ---
echo "--- serviceAccountName ---"
check "auth SA" "kubectl get pod -n apollo11-apps -l app=auth -o jsonpath='{.items[0].spec.serviceAccountName}' | grep -q apollo11"
check "catalog SA" "kubectl get pod -n apollo11-apps -l app=catalog -o jsonpath='{.items[0].spec.serviceAccountName}' | grep -q apollo11"
check "fines SA" "kubectl get pod -n apollo11-apps -l app=fines -o jsonpath='{.items[0].spec.serviceAccountName}' | grep -q apollo11"
check "auth-postgres SA" "kubectl get pod -n apollo11-infra -l app=auth-postgres -o jsonpath='{.items[0].spec.serviceAccountName}' | grep -q apollo11"
echo ""

# --- Stable pod identity (ordinal names) ---
echo "--- Stable Pod Identity (StatefulSet ordinal) ---"
check "auth-postgres-0 pod exists" \
    "kubectl get pods -n apollo11-infra -l app=auth-postgres | grep -q 'auth-postgres-0'"
check "catalog-postgres-0 pod exists" \
    "kubectl get pods -n apollo11-infra -l app=catalog-postgres | grep -q 'catalog-postgres-0'"
check "fines-0 pod exists" \
    "kubectl get pods -n apollo11-apps -l app=fines | grep -q 'fines-0'"
echo ""

echo "============================================"
echo -e "Results: ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC}"
echo "============================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
