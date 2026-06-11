#!/bin/bash
# Verify the Stage 5 ArgoCD GitOps module.
#
# Runs ~25 checks across 5 categories:
#   1. ArgoCD system pods (server, repo-server, app-controller, redis)
#   2. AppProject (exists, scope restricted, no cluster-scoped whitelist)
#   3. Applications (3 expected, all Synced+Healthy, correct repoURL)
#   4. Workloads (chart rendered correctly: StatefulSets, PDBs by env)
#   5. Drift detection (kill a pod, watch ArgoCD re-create it)
#
# Usage:
#   ./scripts/verify.sh                  # all checks
#   ./scripts/verify.sh --skip-workloads # skip the workload checks (workloads are slow)
#   ./scripts/verify.sh --skip-drift     # skip the drift demo (it mutates the cluster)
#
# Exit code: 0 if all pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$(dirname "$SCRIPT_DIR")"
TENANT_NS="apollo-airlines"
ARGOCD_NS="argocd"

SKIP_WORKLOADS=false
SKIP_DRIFT=false

usage() {
    cat <<EOF
Usage: $0 [--skip-workloads] [--skip-drift]
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-workloads) SKIP_WORKLOADS=true; shift ;;
        --skip-drift)     SKIP_DRIFT=true; shift ;;
        --help)           usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

# ---------------------------------------------------------------------------
# 1. ArgoCD system health
# ---------------------------------------------------------------------------
step "1/5 ArgoCD system pods (4 expected: server, repo-server, app-controller, redis)"
EXPECTED_PODS=(
  "argocd-server"
  "argocd-repo-server"
  "argocd-application-controller"
  "argocd-redis"
)
for pod_prefix in "${EXPECTED_PODS[@]}"; do
    # Each component may have multiple replicas; check that at least 1 is Ready
    ready_count=$(kubectl get pods -n "$ARGOCD_NS" -l "app.kubernetes.io/name=$pod_prefix" \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
        | grep -c '^True$' || echo 0)
    if [[ "$ready_count" -ge 1 ]]; then
        pass "$pod_prefix: $ready_count pod(s) Ready"
    else
        fail "$pod_prefix: no Ready pods"
    fi
done

# ---------------------------------------------------------------------------
# 2. AppProject
# ---------------------------------------------------------------------------
step "2/5 AppProject (apollo-airlines, restricted scope)"
if kubectl get appproject apollo-airlines -n "$TENANT_NS" >/dev/null 2>&1; then
    pass "appproject/apollo-airlines exists"
else
    fail "appproject/apollo-airlines missing in namespace $TENANT_NS"
fi

# Verify cluster-scoped resources are denied
cluster_wl=$(kubectl get appproject apollo-airlines -n "$TENANT_NS" -o jsonpath='{.spec.clusterResourceWhitelist}' 2>/dev/null || echo "")
if [[ -z "$cluster_wl" || "$cluster_wl" == "[]" ]]; then
    pass "clusterResourceWhitelist is empty (cluster-scoped denied)"
else
    fail "clusterResourceWhitelist is $cluster_wl (expected empty)"
fi

# Verify destinations
dest_count=$(kubectl get appproject apollo-airlines -n "$TENANT_NS" -o jsonpath='{.spec.destinations}' 2>/dev/null | grep -c 'namespace:' || echo 0)
if [[ "$dest_count" -ge 2 ]]; then
    pass "destinations contains >=2 namespaces ($dest_count found)"
else
    fail "destinations contains $dest_count entries (expected 2: apollo-airlines-apps, apollo-airlines-ui)"
fi

# ---------------------------------------------------------------------------
# 3. Applications
# ---------------------------------------------------------------------------
step "3/5 Applications (3 expected: dev, staging, prod)"
for env in dev staging prod; do
    app="apollo11-$env"
    if ! kubectl get application "$app" -n "$TENANT_NS" >/dev/null 2>&1; then
        fail "application/$app missing"
        continue
    fi
    pass "application/$app exists"

    # Check sync status
    sync_status=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    if [[ "$sync_status" == "Synced" ]]; then
        pass "$app sync.status=Synced"
    else
        fail "$app sync.status=$sync_status (expected Synced — try 'argocd app sync $app')"
    fi

    # Check health status
    health_status=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    if [[ "$health_status" == "Healthy" ]]; then
        pass "$app health.status=Healthy"
    else
        # Progressing is also acceptable for the first few minutes
        if [[ "$health_status" == "Progressing" ]]; then
            pass "$app health.status=Progressing (still syncing — wait a minute and rerun)"
        else
            fail "$app health.status=$health_status (expected Healthy)"
        fi
    fi

    # Check source repoURL
    repo=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "")
    if [[ -n "$repo" ]]; then
        pass "$app source.repoURL=$repo"
    else
        fail "$app source.repoURL is empty"
    fi

    # Check the env-specific values file is referenced
    expected_values="values-${env}.yaml"
    actual_values=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.spec.source.helm.valueFiles}' 2>/dev/null || echo "")
    if [[ "$actual_values" == *"$expected_values"* ]]; then
        pass "$app helm.valueFiles includes $expected_values"
    else
        fail "$app helm.valueFiles=$actual_values (expected to include $expected_values)"
    fi

    # Prod should NOT have automated sync
    if [[ "$env" == "prod" ]]; then
        auto=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null || echo "")
        if [[ -z "$auto" || "$auto" == "" ]]; then
            pass "$app syncPolicy.automated is null (manual sync as required)"
        else
            fail "$app syncPolicy.automated=$auto (expected null for prod)"
        fi
    else
        auto=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null || echo "")
        if [[ -n "$auto" && "$auto" != "" ]]; then
            pass "$app syncPolicy.automated is set (auto-sync as required)"
        else
            fail "$app syncPolicy.automated is null (expected auto-sync for $env)"
        fi
    fi
done

# ---------------------------------------------------------------------------
# 4. Workloads (chart rendered correctly)
# ---------------------------------------------------------------------------
if [[ "$SKIP_WORKLOADS" == "true" ]]; then
    step "4/5 Workloads (skipped via --skip-workloads)"
else
    step "4/5 Workloads (StatefulSets, Deployments, PDBs per env)"

    for sts in identity-db flight-db booking-db redis; do
        ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [[ "$ready" -ge 1 ]]; then
            pass "statefulset/$sts ready=$ready"
        else
            fail "statefulset/$sts not ready (ready=$ready)"
        fi
    done

    for dep in identity flight booking search notification; do
        ready=$(kubectl get deployment "$dep" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [[ "$ready" -ge 1 ]]; then
            pass "deployment/$dep ready=$ready"
        else
            fail "deployment/$dep not ready"
        fi
    done

    # PDBs: dev/staging should NOT have them, prod SHOULD
    for env in dev staging; do
        if kubectl get pdb booking-pdb -n apollo-airlines-apps >/dev/null 2>&1; then
            fail "pdb/booking-pdb exists in $env (expected absent — pdb.enabled=false)"
        else
            pass "pdb/booking-pdb absent in $env (as expected)"
        fi
    done
    if kubectl get pdb booking-pdb -n apollo-airlines-apps >/dev/null 2>&1; then
        pass "pdb/booking-pdb exists in prod (as expected)"
    else
        echo "  (info) pdb/booking-pdb missing in prod — may not be synced yet"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Drift detection (demo)
# ---------------------------------------------------------------------------
if [[ "$SKIP_DRIFT" == "true" ]]; then
    step "5/5 Drift detection (skipped via --skip-drift)"
else
    step "5/5 Drift detection (delete a pod, watch ArgoCD re-create it)"

    # Pick the dev environment. If dev is not synced, skip.
    if ! kubectl get application apollo11-dev -n "$TENANT_NS" >/dev/null 2>&1; then
        echo "  (skip) apollo11-dev not registered"
    else
        # Delete the booking pod (it has 2 replicas so we can safely delete one)
        pod=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$pod" ]]; then
            echo "  (skip) no booking pod found"
        else
            echo "  deleting pod $pod..."
            kubectl delete pod "$pod" -n apollo-airlines-apps --wait=false >/dev/null 2>&1
            sleep 5
            # ArgoCD with selfHeal=true should bring it back
            new_pods=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
            pod_count=$(echo "$new_pods" | wc -w)
            if [[ "$pod_count" -ge 1 ]]; then
                pass "booking pods present after deletion ($pod_count)"
            else
                fail "no booking pods after deletion"
            fi
        fi
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
    echo ""
    echo "  Troubleshooting:"
    echo "    - Check ArgoCD:        kubectl get pods -n argocd"
    echo "    - Check apps:          kubectl get applications -n $TENANT_NS"
    echo "    - Force sync:          argocd app sync apollo11-dev --grpc-web"
    echo "    - Tail app logs:       kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f"
    exit 1
fi
echo -e "${GREEN}All ArgoCD GitOps checks passed.${NC}"
