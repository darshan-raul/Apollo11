#!/bin/bash
# Uninstall ArgoCD from the cluster.
#
# Usage:
#   ./uninstall.sh                  # delete the argocd namespace only
#   ./uninstall.sh --purge         # also delete cluster-scoped CRDs ArgoCD owns
#
# IMPORTANT: this does NOT delete the Applications you registered under
# `apollo-airlines` (those live in a separate namespace). Run
# `scripts/teardown.sh --full` for that.

set -euo pipefail

ARGOCD_NS="argocd"
PURGE=false

usage() {
    cat <<EOF
Usage: $0 [--purge]

Options:
  --purge   Also delete cluster-scoped resources that ArgoCD creates:
             - CustomResourceDefinitions (applications, appprojects, applicationsets)
             - ClusterRoles / ClusterRoleBindings
             - ValidatingWebhookConfigurations / MutatingWebhookConfigurations
  --help    Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --purge) PURGE=true; shift ;;
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

step "1/3 Checking ArgoCD namespace"
if ! kubectl get ns "$ARGOCD_NS" >/dev/null 2>&1; then
    echo "  namespace $ARGOCD_NS not found — ArgoCD is not installed"
    exit 0
fi
ok "namespace $ARGOCD_NS present"

step "2/3 Deleting namespace $ARGOCD_NS"
# ArgoCD has a finalizer on the namespace? No, it doesn't, but the
# argocd-redis pod has a PV that may block. We force-delete stuck pods
# then the namespace with a timeout.
kubectl get pods -n "$ARGOCD_NS" -o name 2>/dev/null | \
    xargs -r -I{} kubectl delete {} -n "$ARGOCD_NS" --force --grace-period=0 2>/dev/null || true
kubectl delete ns "$ARGOCD_NS" --ignore-not-found --timeout 120s 2>&1 | tail -3
ok "namespace $ARGOCD_NS removed"

if [[ "$PURGE" == "true" ]]; then
    step "3/3 Purging cluster-scoped ArgoCD resources"
    # CRDs ArgoCD owns
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'argoproj\.io' || true); do
        kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
    done
    # ClusterRoles / ClusterRoleBindings
    for cr in $(kubectl get clusterrole -o name 2>/dev/null | grep -E 'argocd|argo-cd' || true); do
        kubectl delete "$cr" --ignore-not-found 2>&1 | tail -1
    done
    for crb in $(kubectl get clusterrolebinding -o name 2>/dev/null | grep -E 'argocd|argo-cd' || true); do
        kubectl delete "$crb" --ignore-not-found 2>&1 | tail -1
    done
    # Webhooks (these can block CRD deletion)
    for wh in $(kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep -i argocd || true); do
        kubectl delete "$wh" --ignore-not-found 2>&1 | tail -1
    done
    for wh in $(kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep -i argocd || true); do
        kubectl delete "$wh" --ignore-not-found 2>&1 | tail -1
    done
    ok "cluster-scoped resources purged"
else
    step "3/3 Skipping cluster-scoped purge (run with --purge to remove CRDs)"
fi

ok "ArgoCD uninstall complete"
echo "  If you also want to remove the Applications, run:"
echo "    bash scripts/teardown.sh --full"
