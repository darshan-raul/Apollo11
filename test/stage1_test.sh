#!/bin/bash
# Apollo11 — Stage 1 Self-Check Script
# Verifies all 11 services are correctly deployed to the apollo11 namespace.
# Run from project root: bash test/stage1_test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Colour codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ── Helpers ────────────────────────────────────────────────────────────────────
info()    { echo -e "${BOLD}[INFO]${NC} $1"; }
pass()    { echo -e "${GREEN}[PASS]${NC} $1"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Apollo11 — Stage 1 Self-Check${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

footer() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}  FAILED — $FAIL_COUNT check(s) did not pass${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Fix the failures above, then re-run this script."
        echo "If all pods are pending due to image pull errors, run:"
        echo "  cd stages/stage1 && ./scripts/build-images.sh"
        echo "Then re-apply:"
        echo "  kubectl apply -f stages/stage1/k8s/config/"
        echo "  kubectl apply -f stages/stage1/k8s/infra/ --recursive"
        echo "  kubectl apply -f stages/stage1/k8s/apps/ --recursive"
        echo "  kubectl apply -f stages/stage1/k8s/jobs/"
        exit 1
    else
        echo -e "${GREEN}  ALL CHECKS PASSED${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Stage 1 is complete. What's next:"
        echo "  → Port-forward:  kubectl port-forward -n apollo11 svc/frontend 3000:80"
        echo "  → Access frontend at http://localhost:3000"
        echo "  → Move to Stage 2: bash stages/stage2/scripts/setup.sh"
        exit 0
    fi
}

# ── Counters ──────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
SKIP_REASON=""

check() {
    # check <label> <command>
    local label="$1"; shift
    local cmd="$*"
    if [[ -n "$SKIP_REASON" ]]; then
        warn "$label — SKIPPED ($SKIP_REASON)"
        return 0
    fi
    if eval "$cmd" > /dev/null 2>&1; then
        pass "$label"
        ((PASS_COUNT++))
    else
        fail "$label"
        ((FAIL_COUNT++))
    fi
}

check_output() {
    # check_output <label> <expected> <command>
    local label="$1"; local expected="$2"; shift 2
    local actual
    actual=$(eval "$*" 2>/dev/null || true)
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
        ((PASS_COUNT++))
    else
        fail "$label — got '$actual', expected '$expected'"
        ((FAIL_COUNT++))
    fi
}

check_contains() {
    # check_contains <label> <needle> <command>
    local label="$1"; local needle="$2"; shift 2
    local actual
    actual=$(eval "$*" 2>/dev/null || true)
    if [[ "$actual" == *"$needle"* ]]; then
        pass "$label"
        ((PASS_COUNT++))
    else
        fail "$label — output does not contain '$needle': $actual"
        ((FAIL_COUNT++))
    fi
}

wait_for_pods() {
    # Wait up to 60s for pods in a namespace to not all be Pending
    local ns="$1"
    local waited=0
    while true; do
        local pending
        pending=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | tr ' ' '\n' | grep -c 'Pending' || echo 0)
        local total
        total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        if [[ $pending -lt $total ]] || [[ $waited -ge 60 ]]; then
            break
        fi
        sleep 5
        ((waited+=5))
        info "Waiting for pods to schedule... (${waited}s)"
    done
}

# ── Prereq checks ──────────────────────────────────────────────────────────────
header

info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    SKIP_REASON="kubectl not installed"
    warn "kubectl not found — cannot run cluster checks"
fi

if kubectl cluster-info &> /dev/null; then
    info "Kubernetes cluster is reachable."
else
    SKIP_REASON="no cluster"
    warn "Cannot reach Kubernetes cluster — skipping cluster verification."
fi

if [[ "$SKIP_REASON" == "no cluster" ]] || [[ "$SKIP_REASON" == "kubectl not installed" ]]; then
    warn "Cluster checks will be skipped. Run this script with a live cluster to verify deployments."
fi

# ── 1. Namespace ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[1] Namespace${NC}"
check "apollo11 namespace exists" kubectl get ns apollo11

# ── 2. ConfigMap + Secrets ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2] ConfigMap & Secrets${NC}"
check "apollo11-config ConfigMap exists" kubectl get cm apollo11-config -n apollo11
check "apollo11-secrets Secret exists"  kubectl get secret apollo11-secrets -n apollo11

# ── 3. Infrastructure Deployments (infra layer) ────────────────────────────────
echo ""
echo -e "${BOLD}[3] Infrastructure Deployments (5 infra + 3 app DBs = 8 total)${NC}"

# Wait for pods to schedule before checking Ready
if [[ -z "$SKIP_REASON" ]]; then
    wait_for_pods apollo11
fi

INFRA_DEPS=(
    "auth-postgres"
    "catalog-postgres"
    "circulation-postgres"
    "catalog-redis"
    "notification-redis"
)
for dep in "${INFRA_DEPS[@]}"; do
    check "$dep deployment exists" kubectl get deploy "$dep" -n apollo11
done

# ── 4. App Deployments ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4] Application Deployments (6 services)${NC}"
APP_DEPS=(auth catalog circulation notification fines frontend)
for dep in "${APP_DEPS[@]}"; do
    check "$dep deployment exists" kubectl get deploy "$dep" -n apollo11
done

# ── 5. Deployment Ready status ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5] Deployment Ready Replicas${NC}"
READY_CHECKS=(
    "auth-postgres:1"
    "catalog-postgres:1"
    "circulation-postgres:1"
    "catalog-redis:1"
    "notification-redis:1"
    "auth:2"
    "catalog:2"
    "circulation:2"
    "notification:2"
    "fines:2"
    "frontend:2"
)
for entry in "${READY_CHECKS[@]}"; do
    dep="${entry%%:*}"
    expected="${entry##*:}"
    actual=$(kubectl get deploy "$dep" -n apollo11 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$actual" == "$expected" ]]; then
        pass "$dep ready replicas = $actual"
        ((PASS_COUNT++))
    else
        fail "$dep ready replicas = $actual (expected $expected)"
        ((FAIL_COUNT++))
    fi
done

# ── 6. Services ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[6] Services (7 total)${NC}"
SVC_CHECKS=(
    "auth:8080"
    "catalog:8081"
    "circulation:8082"
    "notification:8083"
    "fines:8084"
    "frontend:80"
    "auth-postgres:5432"
    "catalog-postgres:5432"
    "circulation-postgres:5432"
    "catalog-redis:6379"
    "notification-redis:6380"
)
for entry in "${SVC_CHECKS[@]}"; do
    svc="${entry%%:*}"
    port="${entry##*:}"
    check "$svc service exists with port $port" \
        kubectl get svc "$svc" -n apollo11 -o jsonpath="{.spec.ports[?(@.port==$port)].port}"
done

# ── 7. Init Jobs ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[7] Init Jobs (3 DB setup jobs)${NC}"
JOBS=(init-auth-db init-catalog-db init-circulation-db)
for job in "${JOBS[@]}"; do
    check "$job Job exists" kubectl get job "$job" -n apollo11
    # Check Job succeeded
    phase=$(kubectl get job "$job" -n apollo11 -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
    if [[ "$phase" == "True" ]]; then
        pass "$job completed successfully"
        ((PASS_COUNT++))
    else
        fail "$job has not completed (check pods for errors)"
        ((FAIL_COUNT++))
    fi
done

# ── 8. Health endpoints (port-forward required) ───────────────────────────────
echo ""
echo -e "${BOLD}[8] Health Endpoints (requires port-forward)${NC}"
if [[ -n "$SKIP_REASON" ]]; then
    warn "Health checks skipped — $SKIP_REASON"
else
    # Start port-forward in background for health checks
    info "Starting port-forward to check health endpoints..."
    kubectl port-forward -n apollo11 svc/frontend 3000:80 &> /dev/null &
    PF_PID=$!

    # Give it a moment to establish
    sleep 3

    # Check if port-forward is running
    if ! kill -0 $PF_PID 2>/dev/null; then
        warn "Port-forward failed to start — skipping health checks"
    else
        HEALTH_SVCS=(
            "frontend:http://localhost:3000/health:ok"
            "auth:http://localhost:8080/health:ok"
        )
        for entry in "${HEALTH_SVCS[@]}"; do
            IFS=':' read -r svc url expected <<< "$entry"
            response=$(curl -s --connect-timeout 5 "$url" 2>/dev/null || echo "CONN_ERROR")
            if [[ "$response" == *"$expected"* ]]; then
                pass "$svc health endpoint returns $expected"
                ((PASS_COUNT++))
            else
                fail "$svc health — got: $response (expected contains: $expected)"
                ((FAIL_COUNT++))
            fi
        done

        kill $PF_PID 2>/dev/null || true
    fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────
footer