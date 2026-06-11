#!/bin/bash
# Tear down the Stage 5 ArgoCD GitOps module.
#
# Three levels of teardown:
#   1. (default)  Delete the 3 Applications. ArgoCD removes the resources
#                 they managed (because of the resources-finalizer).
#                 AppProject + ArgoCD system stay.
#
#   2. --apps     Same as default. (Kept for clarity.)
#
#   3. --full     Delete Applications + AppProject + the apollo-airlines
#                 tenant namespace + the entire argocd namespace.
#                 Equivalent to "I want ArgoCD and everything it owned gone."
#
#   4. --purge    Same as --full, plus deletes cluster-scoped CRDs that
#                 ArgoCD owns (applications.argoproj.io, appprojects.argoproj.io, etc.)
#
# WARNING: --full and --purge are destructive. They will delete the
# apollo-airlines-apps and apollo-airlines-ui namespaces (via the
# Application's prune) UNLESS you remove the finalizer first.
#
# Usage:
#   ./scripts/teardown.sh                  # delete 3 Applications only
#   ./scripts/teardown.sh --full           # also remove AppProject + argocd ns
#   ./scripts/teardown.sh --purge          # --full + cluster-scoped CRDs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$ARGOCD_DIR/applications"
PROJECTS_DIR="$ARGOCD_DIR/projects"
TENANT_NS="apollo-airlines"
ARGOCD_NS="argocd"

MODE="apps"   # apps | full | purge

usage() {
    cat <<EOF
Usage: $0 [--full | --purge]

Options:
  (default)     Delete the 3 Applications. ArgoCD prunes the resources
                they managed. AppProject + ArgoCD system remain.
  --full        Also delete the AppProject, the apollo-airlines tenant
                namespace, and the argocd system namespace.
  --purge       Same as --full, plus delete cluster-scoped CRDs
                (applications.argoproj.io, appprojects.argoproj.io, etc.)
  --help        Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)  MODE="full"; shift ;;
        --purge) MODE="purge"; shift ;;
        --help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/3 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster"
fi
ok "cluster reachable"

# ---------------------------------------------------------------------------
# Step 1: Delete the 3 Applications
# ---------------------------------------------------------------------------
step "1/3 Deleting Applications (mode: $MODE)"
DELETED=0
for app_yaml in "$APPS_DIR"/*.yaml; do
    name=$(basename "$app_yaml" .yaml)
    if kubectl get application "$name" -n "$TENANT_NS" >/dev/null 2>&1; then
        # The resources-finalizer on each Application causes ArgoCD to
        # delete all cluster resources it owned BEFORE removing the CR.
        # We wait --timeout=180s because pruning StatefulSets + PVCs is slow.
        echo "  deleting application $name (pruning managed resources)..."
        kubectl delete application "$name" -n "$TENANT_NS" --timeout 180s 2>&1 | tail -1
        DELETED=$((DELETED+1))
    else
        echo "  application $name not found — skipping"
    fi
done
ok "$DELETED application(s) deleted"

# ---------------------------------------------------------------------------
# Step 2 (full/purge only): AppProject + tenant namespace
# ---------------------------------------------------------------------------
if [[ "$MODE" == "full" || "$MODE" == "purge" ]]; then
    step "2/3 Deleting AppProject + tenant namespace"
    if kubectl get appproject apollo-airlines -n "$TENANT_NS" >/dev/null 2>&1; then
        kubectl delete appproject apollo-airlines -n "$TENANT_NS" 2>&1 | tail -1
        ok "appproject/apollo-airlines deleted"
    else
        echo "  appproject/apollo-airlines not found — skipping"
    fi
    if kubectl get ns "$TENANT_NS" >/dev/null 2>&1; then
        kubectl delete ns "$TENANT_NS" --ignore-not-found --timeout 60s 2>&1 | tail -1
        ok "namespace $TENANT_NS deleted"
    else
        echo "  namespace $TENANT_NS not found — skipping"
    fi
else
    step "2/3 Skipping (run with --full or --purge to remove AppProject)"
fi

# ---------------------------------------------------------------------------
# Step 3 (full/purge only): ArgoCD system namespace
# ---------------------------------------------------------------------------
if [[ "$MODE" == "full" || "$MODE" == "purge" ]]; then
    step "3/3 Deleting ArgoCD system namespace"
    if kubectl get ns "$ARGOCD_NS" >/dev/null 2>&1; then
        # Force-delete stuck pods (the argocd-redis pod's PVC can block
        # namespace deletion)
        kubectl get pods -n "$ARGOCD_NS" -o name 2>/dev/null | \
            xargs -r -I{} kubectl delete {} -n "$ARGOCD_NS" --force --grace-period=0 2>/dev/null || true
        kubectl delete ns "$ARGOCD_NS" --ignore-not-found --timeout 120s 2>&1 | tail -1
        ok "namespace $ARGOCD_NS deleted"
    else
        echo "  namespace $ARGOCD_NS not found — skipping"
    fi

    if [[ "$MODE" == "purge" ]]; then
        echo "  purging cluster-scoped CRDs..."
        for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'argoproj\.io' || true); do
            kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
        done
        for cr in $(kubectl get clusterrole -o name 2>/dev/null | grep -E 'argocd|argo-cd' || true); do
            kubectl delete "$cr" --ignore-not-found 2>&1 | tail -1
        done
        for crb in $(kubectl get clusterrolebinding -o name 2>/dev/null | grep -E 'argocd|argo-cd' || true); do
            kubectl delete "$crb" --ignore-not-found 2>&1 | tail -1
        done
        ok "cluster-scoped ArgoCD resources purged"
    fi
else
    step "3/3 Skipping (run with --full or --purge to remove ArgoCD system)"
fi

ok "Teardown complete (mode: $MODE)"
echo ""
echo "  Remaining state:"
kubectl get applications -n "$TENANT_NS" 2>/dev/null | head -5 || echo "    (no applications namespace)"
kubectl get ns "$ARGOCD_NS" 2>/dev/null && echo "    (argocd ns still present)" || echo "    (argocd ns removed)"
