#!/bin/bash
# Tear down Stage 5 — symmetric to apply.sh.
#
# Usage:
#   ./scripts/teardown.sh                       # helm uninstall (default)
#   ./scripts/teardown.sh --mode kustomize      # kubectl delete -k overlays/dev
#   ./scripts/teardown.sh --purge               # also delete namespaces + cluster-scoped resources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"
RELEASE_NAME="apollo11"

MODE="helm"
ENV="dev"
PURGE=false

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--purge]

Options:
  --mode MODE   helm (default) | kustomize
  --env ENV     dev (default) | staging | prod — used by --mode kustomize
  --purge       Also delete apollo-airlines-apps, apollo-airlines-ui, envoy-gateway-system,
                metallb-system namespaces and their cluster-scoped resources
  --help        Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)  MODE="$2"; shift 2 ;;
        --env)   ENV="$2"; shift 2 ;;
        --purge) PURGE=true; shift ;;
        --help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "Tearing down (mode: $MODE, env: $ENV, purge: $PURGE)"

if [[ "$MODE" == "helm" ]]; then
    if helm list -n apollo-airlines-apps 2>/dev/null | grep -q "$RELEASE_NAME"; then
        step "Helm uninstall"
        helm uninstall "$RELEASE_NAME" -n apollo-airlines-apps --wait --timeout 5m 2>&1 | tail -3
        ok "helm uninstall complete"
    else
        echo "  Helm release '$RELEASE_NAME' not found — skipping"
    fi
elif [[ "$MODE" == "kustomize" ]]; then
    OVERLAY_DIR="$STAGE_DIR/overlays/$ENV"
    step "Kustomize delete"
    kubectl delete -k "$OVERLAY_DIR" --ignore-not-found 2>&1 | tail -3
    ok "kustomize overlay deleted"
fi

if [[ "$PURGE" == "true" ]]; then
    step "Purging namespaces + cluster-scoped resources"

    # Force-delete stuck pods (the chart's CRDs may block normal deletion)
    for ns in apollo-airlines-apps apollo-airlines-ui; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            echo "  Patching namespace $ns for force-deletion..."
            kubectl get pods -n "$ns" -o name 2>/dev/null | xargs -r -I{} kubectl delete {} -n "$ns" --force --grace-period=0 2>/dev/null || true
        fi
    done

    # Namespaces (in order: data plane, then access plane)
    for ns in apollo-airlines-apps apollo-airlines-ui; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            kubectl delete ns "$ns" --ignore-not-found --timeout 60s 2>&1 | tail -2
        fi
    done

    # Gateway + access stack
    step "Purging Envoy Gateway + MetalLB"
    for ns in envoy-gateway-system metallb-system; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            timeout 60 kubectl delete ns "$ns" --ignore-not-found 2>&1 | tail -2 || \
                kubectl patch ns "$ns" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
    done

    # CRDs (cluster-scoped — left behind by helm uninstall sometimes)
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'envoyproxy|gateway\.networking|metallb' || true); do
        kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
    done

    ok "purge complete"
fi

ok "Stage 5 teardown complete"
