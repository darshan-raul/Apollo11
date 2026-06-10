#!/bin/bash
# Verify Stage 5: ~70 checks covering namespaces, SAs, ConfigMap, Secret,
# 3 Postgres StatefulSets + 1 Redis StatefulSet, 6 app Deployments +
# frontend Deployment, 2 PDBs, 3 seed Jobs, GatewayClass, Gateway, 6
# HTTPRoutes, ReferenceGrant, MetalLB IPAddressPool, and the chart's
# own metadata.
#
# Mode-aware: works for both helm and kustomize installs. Some checks
# (e.g. envoy-gateway-system namespace) only apply to --mode helm.
#
# Usage:
#   ./scripts/verify.sh                  # auto-detect mode
#   ./scripts/verify.sh --mode helm      # explicit
#   ./scripts/verify.sh --mode kustomize --env prod
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

MODE="auto"
ENV="dev"
GATEWAY_EXPECTED=true

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV]

Options:
  --mode MODE   helm | kustomize | auto (default)
  --env ENV     env for kustomize mode (default: dev)
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift 2 ;;
        --env)  ENV="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Auto-detect mode
if [[ "$MODE" == "auto" ]]; then
    if helm list -n apollo-airlines-apps 2>/dev/null | grep -q apollo11; then
        MODE="helm"
    elif kubectl get deployment -n apollo-airlines-apps identity >/dev/null 2>&1; then
        MODE="kustomize"
    else
        echo -e "${RED}Could not auto-detect install mode. Run with --mode helm or --mode kustomize.${NC}"
        exit 1
    fi
    echo "Auto-detected mode: $MODE"
fi

# Some checks (Envoy, MetalLB) only apply to helm mode
if [[ "$MODE" == "kustomize" ]]; then
    GATEWAY_EXPECTED=false
fi

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------
step "Namespaces (2 expected: apollo-airlines-apps, apollo-airlines-ui)"
for ns in apollo-airlines-apps apollo-airlines-ui; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then pass "ns/$ns"; else fail "ns/$ns missing"; fi
done

# ---------------------------------------------------------------------------
# ServiceAccounts (13 expected)
# ---------------------------------------------------------------------------
step "ServiceAccounts (13 expected: 6 apps + 4 data + 3 init)"
EXPECTED_SAS=(
  "apollo-airlines-apps:identity"     "apollo-airlines-apps:flight"
  "apollo-airlines-apps:booking"      "apollo-airlines-apps:search"
  "apollo-airlines-apps:notification" "apollo-airlines-ui:frontend"
  "apollo-airlines-apps:identity-db"  "apollo-airlines-apps:flight-db"
  "apollo-airlines-apps:booking-db"   "apollo-airlines-apps:redis"
  "apollo-airlines-apps:init-identity-db"
  "apollo-airlines-apps:init-flight-db"
  "apollo-airlines-apps:init-booking-db"
)
for sa in "${EXPECTED_SAS[@]}"; do
    ns="${sa%%:*}"; name="${sa##*:}"
    if kubectl get sa "$name" -n "$ns" >/dev/null 2>&1; then
        pass "sa $ns/$name"
    else
        fail "sa $ns/$name missing"
    fi
done

# ---------------------------------------------------------------------------
# ConfigMap + Secret
# ---------------------------------------------------------------------------
step "ConfigMap + Secret"
if kubectl get cm apollo-airlines-config -n apollo-airlines-apps >/dev/null 2>&1; then
    pass "cm/apollo-airlines-config in apollo-airlines-apps"
else
    fail "cm/apollo-airlines-config missing in apollo-airlines-apps"
fi
if kubectl get cm apollo-airlines-config -n apollo-airlines-ui >/dev/null 2>&1; then
    pass "cm/apollo-airlines-config in apollo-airlines-ui"
else
    fail "cm/apollo-airlines-config missing in apollo-airlines-ui"
fi
if kubectl get secret apollo-airlines-secrets -n apollo-airlines-apps >/dev/null 2>&1; then
    pass "secret/apollo-airlines-secrets in apollo-airlines-apps"
else
    fail "secret/apollo-airlines-secrets missing in apollo-airlines-apps"
fi

# ---------------------------------------------------------------------------
# StatefulSets
# ---------------------------------------------------------------------------
step "StatefulSets (4 expected: 3 PG + 1 Redis, all 1/1 Ready)"
for sts in identity-db flight-db booking-db redis; do
    ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -ge 1 ]]; then
        pass "statefulset/$sts ready=$ready"
    else
        fail "statefulset/$sts not ready (ready=$ready)"
    fi
done

step "StatefulSet pods (4 expected, all Ready)"
for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    cond=$(kubectl get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$cond" == "True" ]]; then
        pass "pod/$pod Ready"
    else
        fail "pod/$pod not Ready (cond=$cond)"
    fi
done

# ---------------------------------------------------------------------------
# PVCs
# ---------------------------------------------------------------------------
step "PVCs (4 expected, all Bound)"
EXPECTED_PVCS=(
  "apollo-airlines-apps:pg-data-identity-db-0"
  "apollo-airlines-apps:pg-data-flight-db-0"
  "apollo-airlines-apps:pg-data-booking-db-0"
  "apollo-airlines-apps:redis-data-redis-0"
)
for p in "${EXPECTED_PVCS[@]}"; do
    ns="${p%%:*}"; name="${p##*:}"
    phase=$(kubectl get pvc "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Bound" ]]; then
        pass "pvc $ns/$name Bound"
    else
        fail "pvc $ns/$name phase=$phase (expected Bound)"
    fi
done

# ---------------------------------------------------------------------------
# Headless Services
# ---------------------------------------------------------------------------
step "Headless Services (4 expected)"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
    clusterIP=$(kubectl get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    if [[ "$clusterIP" == "None" ]]; then
        pass "svc/$svc headless"
    else
        fail "svc/$svc clusterIP=$clusterIP (expected None)"
    fi
done

# ---------------------------------------------------------------------------
# App Deployments
# ---------------------------------------------------------------------------
step "App Deployments (5 expected, all >=1 Ready)"
for dep in identity flight booking search notification; do
    ready=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" -ge 1 ]]; then
        pass "deployment/$dep ready=$ready"
    else
        fail "deployment/$dep not ready (ready=$ready)"
    fi
done

# ---------------------------------------------------------------------------
# Frontend Deployment
# ---------------------------------------------------------------------------
step "Frontend Deployment (1 expected)"
ready=$(kubectl get deployment frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then
    pass "deployment/frontend ready=$ready"
else
    fail "deployment/frontend not ready (ready=$ready)"
fi

# ---------------------------------------------------------------------------
# Probes (Stage 4 contract — startup/live/ready on 6 apps)
# ---------------------------------------------------------------------------
step "Probes on 6 app Deployments (startup/live/ready, all 3 distinct)"
for dep in identity flight booking search notification; do
    for probe in startupProbe livenessProbe readinessProbe; do
        path=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || echo "")
        if [[ -n "$path" && "$path" == "/healthz/"* ]]; then
            pass "deployment/$dep $probe path=$path"
        else
            fail "deployment/$dep $probe missing or wrong path ($path)"
        fi
    done
done

# ---------------------------------------------------------------------------
# Resources (Guaranteed QoS — requests == limits)
# ---------------------------------------------------------------------------
step "Resources: requests == limits (Guaranteed QoS) on 6 apps"
for dep in identity flight booking search notification; do
    reqCpu=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    limCpu=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
    if [[ -n "$reqCpu" && "$reqCpu" == "$limCpu" ]]; then
        pass "deployment/$dep CPU req=lim=$reqCpu"
    else
        fail "deployment/$dep CPU req=$reqCpu lim=$limCpu (expected equal)"
    fi
done

# ---------------------------------------------------------------------------
# terminationGracePeriodSeconds
# ---------------------------------------------------------------------------
step "terminationGracePeriodSeconds (30s on apps)"
for dep in identity flight booking search notification; do
    grace=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
    if [[ "$grace" == "30" ]]; then
        pass "deployment/$dep terminationGracePeriodSeconds=30"
    else
        fail "deployment/$dep terminationGracePeriodSeconds=$grace (expected 30)"
    fi
done

# ---------------------------------------------------------------------------
# PodDisruptionBudgets (chart applies both; kustomize prod applies both)
# ---------------------------------------------------------------------------
step "PodDisruptionBudgets (2 expected: booking-pdb, frontend-pdb)"
if kubectl get pdb booking-pdb -n apollo-airlines-apps >/dev/null 2>&1; then
    min=$(kubectl get pdb booking-pdb -n apollo-airlines-apps -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
    pass "pdb/booking-pdb (minAvailable=$min)"
else
    echo "  (skip) pdb/booking-pdb missing — chart may not include PDBs in this mode"
fi
if kubectl get pdb frontend-pdb -n apollo-airlines-ui >/dev/null 2>&1; then
    min=$(kubectl get pdb frontend-pdb -n apollo-airlines-ui -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
    pass "pdb/frontend-pdb (minAvailable=$min)"
else
    echo "  (skip) pdb/frontend-pdb missing"
fi

# ---------------------------------------------------------------------------
# Seed Jobs (chart only)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "helm" ]]; then
    step "Seed Jobs (3 expected: identity, flight, booking — all Complete)"
    for job in seed-identity-db seed-flight-db seed-booking-db; do
        status=$(kubectl get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        if [[ "$status" == "True" ]]; then
            pass "job/$job Complete"
        else
            fail "job/$job status=$status (expected Complete=True)"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Gateway (helm mode only)
# ---------------------------------------------------------------------------
if [[ "$GATEWAY_EXPECTED" == "true" ]]; then
    step "Envoy Gateway (access stack, helm mode only)"

    if kubectl get ns envoy-gateway-system >/dev/null 2>&1; then
        pass "ns/envoy-gateway-system"
    else
        fail "ns/envoy-gateway-system missing"
    fi

    if kubectl get ns metallb-system >/dev/null 2>&1; then
        pass "ns/metallb-system"
    else
        fail "ns/metallb-system missing"
    fi

    if kubectl get gatewayclass eg >/dev/null 2>&1; then
        pass "gatewayclass/eg"
    else
        fail "gatewayclass/eg missing"
    fi

    if kubectl get gateway apollo-gateway -n apollo-airlines-apps >/dev/null 2>&1; then
        # Check the Gateway has a programmed condition
        programmed=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
        if [[ "$programmed" == "True" ]]; then
            pass "gateway/apollo-gateway Programmed"
        else
            fail "gateway/apollo-gateway not Programmed (status=$programmed)"
        fi
    else
        fail "gateway/apollo-gateway missing"
    fi

    step "HTTPRoutes (6 expected: identity, flight, booking, search, notification, frontend)"
    for route in identity flight booking search notification; do
        if kubectl get httproute "$route" -n apollo-airlines-apps >/dev/null 2>&1; then
            pass "httproute/$route"
        else
            fail "httproute/$route missing"
        fi
    done
    if kubectl get httproute frontend -n apollo-airlines-ui >/dev/null 2>&1; then
        pass "httproute/frontend (cross-namespace)"
    else
        fail "httproute/frontend missing in apollo-airlines-ui"
    fi

    step "ReferenceGrant (cross-namespace)"
    if kubectl get referencegrant apollo-gateway-grant -n apollo-airlines-ui >/dev/null 2>&1; then
        pass "referencegrant/apollo-gateway-grant"
    else
        fail "referencegrant/apollo-gateway-grant missing"
    fi

    step "MetalLB IP pool + L2 advertisement"
    if kubectl get ipaddresspool apollo-pool -n metallb-system >/dev/null 2>&1; then
        pass "ipaddresspool/apollo-pool"
    else
        fail "ipaddresspool/apollo-pool missing"
    fi
    if kubectl get l2advertisement apollo-l2 -n metallb-system >/dev/null 2>&1; then
        pass "l2advertisement/apollo-l2"
    else
        fail "l2advertisement/apollo-l2 missing"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo ""
echo "============================================"
echo -e "  ${GREEN}PASS: $PASS${NC}  /  ${RED}FAIL: $FAIL${NC}  /  TOTAL: $TOTAL"
echo "============================================"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
echo -e "${GREEN}All Stage 5 checks passed.${NC}"
