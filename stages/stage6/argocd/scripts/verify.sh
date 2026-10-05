#!/bin/bash
# Verify the Stage 6 Argo CD module: controller health, project boundaries,
# three isolated tenant Applications, shared observability, and real self-heal.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/context.sh"
apollo_context_guard

ARGOCD_NS="argocd"
SKIP_WORKLOADS=false
SKIP_DRIFT=false
EXPECTED_REPO="https://github.com/darshan-raul/Apollo11.git"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-workloads) SKIP_WORKLOADS=true; shift ;;
        --skip-drift) SKIP_DRIFT=true; shift ;;
        --repo-url) EXPECTED_REPO="$2"; shift 2 ;;
        --help) echo "Usage: $0 [--skip-workloads] [--skip-drift] [--repo-url URL]"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

step "1/5 Argo CD control plane"
for component in argocd-server argocd-repo-server argocd-application-controller argocd-redis; do
    ready=$(kubectl get pods -n "$ARGOCD_NS" -l "app.kubernetes.io/name=$component" \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
        | grep -c '^True$' || true)
    if [[ "$ready" -ge 1 ]]; then pass "$component has $ready Ready pod(s)"; else fail "$component has no Ready pod"; fi
done

step "2/5 Shared platform and AppProject boundary"
for crd in applications.argoproj.io gateways.gateway.networking.k8s.io ipaddresspools.metallb.io servicemonitors.monitoring.coreos.com; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then pass "crd/$crd"; else fail "crd/$crd missing"; fi
done
if kubectl get gatewayclass eg >/dev/null 2>&1; then pass "shared gatewayclass/eg"; else fail "shared gatewayclass/eg missing"; fi
if kubectl get ipaddresspool apollo-pool -n metallb-system >/dev/null 2>&1; then pass "shared ipaddresspool/apollo-pool"; else fail "shared ipaddresspool/apollo-pool missing"; fi

if kubectl get appproject apollo-airlines -n "$ARGOCD_NS" >/dev/null 2>&1; then pass "appproject/apollo-airlines"; else fail "appproject/apollo-airlines missing"; fi
cluster_scope=$(kubectl get appproject apollo-airlines -n "$ARGOCD_NS" -o jsonpath='{.spec.clusterResourceWhitelist}' 2>/dev/null || echo "")
if [[ -z "$cluster_scope" || "$cluster_scope" == "[]" ]]; then pass "tenant Applications cannot create cluster-scoped resources"; else fail "clusterResourceWhitelist=$cluster_scope"; fi

expected_namespaces=(
  apollo-airlines-dev-apps apollo-airlines-dev-ui
  apollo-airlines-staging-apps apollo-airlines-staging-ui
  apollo-airlines-prod-apps apollo-airlines-prod-ui
  apollo-observability
)
destinations=$(kubectl get appproject apollo-airlines -n "$ARGOCD_NS" \
    -o jsonpath='{range .spec.destinations[*]}{.namespace}{"\n"}{end}' 2>/dev/null || echo "")
for ns in "${expected_namespaces[@]}"; do
    if grep -qx "$ns" <<<"$destinations"; then pass "project destination $ns"; else fail "project destination $ns missing"; fi
    if kubectl get namespace "$ns" >/dev/null 2>&1; then pass "namespace/$ns"; else fail "namespace/$ns missing"; fi
done

step "3/5 Three isolated tenant Applications plus shared observability"
for env in dev staging prod; do
    app="apollo11-$env"
    apps_ns="apollo-airlines-$env-apps"
    ui_ns="apollo-airlines-$env-ui"
    if ! kubectl get application "$app" -n "$ARGOCD_NS" >/dev/null 2>&1; then fail "application/$app missing"; continue; fi
    pass "application/$app"

    repo=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "")
    if [[ "$repo" == "$EXPECTED_REPO" ]]; then pass "$app uses expected repo"; else fail "$app repoURL=$repo"; fi
    destination=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || echo "")
    if [[ "$destination" == "$apps_ns" ]]; then pass "$app destination=$apps_ns"; else fail "$app destination=$destination"; fi
    parameters=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{range .spec.source.helm.parameters[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null || echo "")
    for expected in "namespaces.apps=$apps_ns" "namespaces.ui=$ui_ns" "gateway.createClass=false" "metallb.enabled=false" "observability.enabled=false"; do
        if grep -qx "$expected" <<<"$parameters"; then pass "$app parameter $expected"; else fail "$app missing parameter $expected"; fi
    done

    automated=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null || echo "")
    if [[ "$env" == "prod" ]]; then
        if [[ -z "$automated" ]]; then pass "$app is manual-sync"; else fail "$app unexpectedly enables automated sync"; fi
    else
        if [[ -n "$automated" ]]; then pass "$app enables automated sync"; else fail "$app automated sync missing"; fi
        sync=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        health=$(kubectl get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        if [[ "$sync" == "Synced" ]]; then pass "$app sync=Synced"; else fail "$app sync=$sync"; fi
        if [[ "$health" == "Healthy" ]]; then pass "$app health=Healthy"; else fail "$app health=$health"; fi
    fi
done

if kubectl get application apollo11-observability -n "$ARGOCD_NS" >/dev/null 2>&1; then
    pass "application/apollo11-observability"
    obs_destination=$(kubectl get application apollo11-observability -n "$ARGOCD_NS" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || echo "")
    [[ "$obs_destination" == "apollo-observability" ]] && pass "observability destination=apollo-observability" || fail "observability destination=$obs_destination"
    obs_sync=$(kubectl get application apollo11-observability -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    obs_health=$(kubectl get application apollo11-observability -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    [[ "$obs_sync" == "Synced" ]] && pass "observability sync=Synced" || fail "observability sync=$obs_sync"
    [[ "$obs_health" == "Healthy" ]] && pass "observability health=Healthy" || fail "observability health=$obs_health"
else
    fail "application/apollo11-observability missing"
fi

if [[ "$SKIP_WORKLOADS" == "true" ]]; then
    step "4/5 Environment workloads (skipped)"
else
    step "4/5 Dev/staging workloads and shared observability are healthy"
    for env in dev staging; do
        apps_ns="apollo-airlines-$env-apps"; ui_ns="apollo-airlines-$env-ui"
        for workload in identity flight booking search notification; do
            ready=$(kubectl get deployment "$workload" -n "$apps_ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
            if [[ "$ready" -ge 1 ]]; then pass "$env deployment/$workload ready=$ready"; else fail "$env deployment/$workload not ready"; fi
        done
        ready=$(kubectl get deployment frontend -n "$ui_ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [[ "$ready" -ge 1 ]]; then pass "$env deployment/frontend ready=$ready"; else fail "$env deployment/frontend not ready"; fi
        for workload in identity-db flight-db booking-db redis; do
            ready=$(kubectl get statefulset "$workload" -n "$apps_ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
            if [[ "$ready" -ge 1 ]]; then pass "$env statefulset/$workload ready=$ready"; else fail "$env statefulset/$workload not ready"; fi
        done
        gateway=$(kubectl get gateway apollo-gateway -n "$apps_ns" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
        if [[ "$gateway" == "True" ]]; then pass "$env gateway Programmed"; else fail "$env gateway status=$gateway"; fi
    done
    for workload in grafana loki tempo; do
        ready=$(kubectl get deployment "$workload" -n apollo-observability -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        [[ "$ready" -ge 1 ]] && pass "observability deployment/$workload ready=$ready" || fail "observability deployment/$workload not ready"
    done
    ready=$(kubectl get statefulset prometheus-apollo -n apollo-observability -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    [[ "$ready" -ge 1 ]] && pass "observability statefulset/prometheus-apollo ready=$ready" || fail "observability statefulset/prometheus-apollo not ready"
fi

if [[ "$SKIP_DRIFT" == "true" ]]; then
    step "5/5 Argo CD self-heal (skipped)"
else
    step "5/5 Argo CD self-heals declarative drift"
    dev_ns="apollo-airlines-dev-apps"
    original=$(kubectl get deployment booking -n "$dev_ns" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
    if [[ "$original" != "1" ]]; then
        fail "dev booking replicas=$original before drift test (expected 1)"
    else
        kubectl patch deployment booking -n "$dev_ns" --type merge -p '{"spec":{"replicas":2}}' >/dev/null
        # Avoid waiting for the normal reconciliation interval; this requests
        # an immediate comparison, after which automated selfHeal must revert.
        kubectl annotate application apollo11-dev -n "$ARGOCD_NS" \
            argocd.argoproj.io/refresh=hard --overwrite >/dev/null
        restored=false
        for _ in $(seq 1 45); do
            replicas=$(kubectl get deployment booking -n "$dev_ns" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
            if [[ "$replicas" == "1" ]]; then restored=true; break; fi
            sleep 2
        done
        if [[ "$restored" == "true" ]]; then pass "dev booking replicas self-healed 2 -> 1"; else fail "Argo CD did not self-heal dev booking replicas within 90s"; fi
    fi
fi

TOTAL=$((PASS+FAIL))
echo ""
echo "============================================"
echo -e "  ${GREEN}PASS: $PASS${NC}  /  ${RED}FAIL: $FAIL${NC}  /  TOTAL: $TOTAL"
echo "============================================"
[[ "$FAIL" -eq 0 ]] || exit 1
echo -e "${GREEN}All Argo CD GitOps checks passed.${NC}"
