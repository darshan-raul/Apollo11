#!/bin/bash
# Apollo11 — Stage 1 Self-Check Script
# Verifies all 10 services are correctly deployed to the apollo-airlines namespace.
# Run from project root: bash test/stage1_test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0

info()    { echo -e "${BOLD}[INFO]${NC} $1"; }
pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Apollo11 — Stage 1 Self-Check (Apollo Airlines)${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

footer() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}  FAILED — $FAIL check(s) did not pass${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Fix the failures above, then re-run this script."
        echo "If all pods are pending due to image pull errors, run:"
        echo "  cd stages/stage1 && ./scripts/build-images.sh"
        echo "Then re-apply:"
        echo "  kubectl apply -k stages/stage1/k8s/"
        exit 1
    else
        echo -e "${GREEN}  ALL CHECKS PASSED${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Stage 1 is complete. What's next:"
        echo "  → kubectl port-forward -n apollo-airlines svc/frontend 3000:3000"
        echo "  → Access frontend at http://localhost:3000"
        echo "  → Move to Stage 2: bash test/stage2_test.sh"
        exit 0
    fi
}

check() {
    local label="$1"; shift
    if eval "$@" > /dev/null 2>&1; then
        pass "$label"
    else
        fail "$label"
    fi
}

wait_for_pods() {
    local ns="$1"; local waited=0
    while true; do
        local pending
        pending=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -c 'Pending' || echo 0)
        local total
        total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        if [[ $pending -lt $total ]] || [[ $waited -ge 90 ]]; then
            break
        fi
        sleep 5; ((waited+=5))
        info "Waiting for pods to schedule... (${waited}s)"
    done
}

header

if ! command -v kubectl &> /dev/null; then
    warn "kubectl not found — cannot run cluster checks"
    echo "  Install kubectl or ensure it's in your PATH"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    warn "Cannot reach Kubernetes cluster — skipping live verification"
fi

# ── 1. Namespace ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[1] Namespace${NC}"
check "apollo-airlines namespace exists" kubectl get ns apollo-airlines

# ── 2. ConfigMap & Secrets ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2] ConfigMap & Secrets${NC}"
check "apollo-airlines-config ConfigMap exists" kubectl get cm apollo-airlines-config -n apollo-airlines
check "apollo-airlines-secrets Secret exists"  kubectl get secret apollo-airlines-secrets -n apollo-airlines

# ── 3. Infrastructure Deployments ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3] Infrastructure Deployments (4 infra DBs)${NC}"
wait_for_pods apollo-airlines

for dep in identity-db flight-db booking-db redis; do
    check "$dep deployment exists" kubectl get deploy "$dep" -n apollo-airlines
done

# ── 4. App Deployments ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4] Application Deployments (6 services)${NC}"
for dep in identity flight booking search notification frontend; do
    check "$dep deployment exists" kubectl get deploy "$dep" -n apollo-airlines
done

# ── 5. Deployment Ready status ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5] Deployment Ready Replicas${NC}"
READY_CHECKS=(
    "identity-db:1"
    "flight-db:1"
    "booking-db:1"
    "redis:1"
    "identity:2"
    "flight:2"
    "booking:2"
    "search:2"
    "notification:2"
    "frontend:2"
)
for entry in "${READY_CHECKS[@]}"; do
    IFS=':' read -r dep expected <<< "$entry"
    actual=$(kubectl get deploy "$dep" -n apollo-airlines -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$actual" == "$expected" ]]; then
        pass "$dep ready replicas = $actual"
    else
        fail "$dep ready replicas = $actual (expected $expected)"
    fi
done

# ── 6. Services ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[6] Services (10 total)${NC}"
declare -A SERVICES
SERVICES=(
    ["identity"]="8080"
    ["flight"]="8081"
    ["booking"]="8082"
    ["search"]="8083"
    ["notification"]="8084"
    ["frontend"]="3000"
    ["identity-db"]="5432"
    ["flight-db"]="5432"
    ["booking-db"]="5432"
    ["redis"]="6379"
)
for svc in "${!SERVICES[@]}"; do
    port="${SERVICES[$svc]}"
    check "$svc service exists with port $port" \
        kubectl get svc "$svc" -n apollo-airlines -o jsonpath="{.spec.ports[?(@.port==$port)].port}"
done

# ── 7. Init Jobs ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[7] Init Jobs (3 DB setup jobs)${NC}"
for job in init-identity-db init-flight-db init-booking-db; do
    check "$job Job exists" kubectl get job "$job" -n apollo-airlines
    succeeded=$(kubectl get job "$job" -n apollo-airlines -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$succeeded" == "1" ]]; then
        pass "$job completed successfully"
    else
        fail "$job has not completed (succeeded=$succeeded)"
    fi
done

# ── 8. ConfigMap init scripts ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[8] Init ConfigMaps${NC}"
for cm in identity-init-script flight-init-script booking-init-script; do
    check "$cm ConfigMap exists" kubectl get cm "$cm" -n apollo-airlines
done

# ── Summary ────────────────────────────────────────────────────────────────────
footer