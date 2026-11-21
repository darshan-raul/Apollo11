#!/bin/bash
# Tear down Stage 6 — symmetric to apply.sh.
#
# Usage:
#   ./scripts/teardown.sh                       # helm uninstall (default)
#   ./scripts/teardown.sh --mode kustomize      # kubectl delete -k overlays/dev
#   ./scripts/teardown.sh --purge               # also delete namespaces + cluster-scoped resources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_NAME="apollo11"

MODE="helm"
ENV="dev"
PURGE=false

usage() {
    local code="${1:-1}"
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--release NAME] [--context CTX] [--purge]

Options:
  --mode MODE     helm (default) | kustomize
  --env ENV       dev (default) | staging | prod — used by --mode kustomize
  --release NAME  Helm release name (default: apollo11)
  --context CTX   Kubernetes context (kind-apollo11 or kind-apollo11-dev)
  --purge         Also delete the app, UI, observability, Envoy Gateway, and
                  MetalLB namespaces plus their cluster-scoped resources
  --help          Show this help
EOF
    exit "$code"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)    [[ $# -ge 2 ]] || { echo "--mode requires a value" >&2; usage 2; }; MODE="$2"; shift 2 ;;
        --env)     [[ $# -ge 2 ]] || { echo "--env requires a value" >&2; usage 2; }; ENV="$2"; shift 2 ;;
        --release) [[ $# -ge 2 ]] || { echo "--release requires a value" >&2; usage 2; }; RELEASE_NAME="$2"; shift 2 ;;
        --context) [[ $# -ge 2 ]] || { echo "--context requires a value" >&2; usage 2; }; export KUBE_CONTEXT="$2"; shift 2 ;;
        --purge)   PURGE=true; shift ;;
        --help|-h) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

case "$MODE" in
    helm|kustomize) ;;
    *) echo "Invalid --mode '$MODE' (expected helm or kustomize)" >&2; usage 2 ;;
esac
case "$ENV" in
    dev|staging|prod) ;;
    *) echo "Invalid --env '$ENV' (expected dev, staging, or prod)" >&2; usage 2 ;;
esac

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/context.sh"
apollo_context_guard

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Controller bundle deletion includes CRDs even without --purge.
apollo_assert_exclusive_platform

step "Tearing down (mode: $MODE, env: $ENV, purge: $PURGE)"

if [[ "$MODE" == "helm" ]]; then
    if helm list -n apollo-airlines-apps 2>/dev/null | grep -qw "$RELEASE_NAME"; then
        step "Helm uninstall"
        helm uninstall "$RELEASE_NAME" -n apollo-airlines-apps --wait --timeout 5m 2>&1 | tail -3
        ok "helm uninstall complete"
    else
        echo "  Helm release '$RELEASE_NAME' not found — skipping"
    fi
elif [[ "$MODE" == "kustomize" ]]; then
    OVERLAY_DIR="$STAGE_DIR/overlays/$ENV"
    kubectl delete prometheus apollo -n apollo-observability --ignore-not-found --wait=true --timeout=90s 2>/dev/null || true
    step "Kustomize delete"
    kubectl delete -k "$OVERLAY_DIR" --ignore-not-found 2>&1 | tail -3
    ok "kustomize overlay deleted"
fi

OPERATOR_BUNDLE="$STAGE_DIR/bundles/prometheus-operator-v0.93.0.yaml"
if [[ -f "$OPERATOR_BUNDLE" ]]; then
    step "Removing Prometheus Operator bundle"
    kubectl delete -f "$OPERATOR_BUNDLE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
fi

if [[ "$PURGE" == "true" ]]; then
    step "Purging namespaces + cluster-scoped resources"

    finalize_ns() {
        local target_ns="$1"
        kubectl get ns "$target_ns" -o json 2>/dev/null \
            | python3 -c 'import json,sys
ns = json.load(sys.stdin)
ns.setdefault("spec", {})["finalizers"] = []
print(json.dumps(ns))' \
            | kubectl replace --raw "/api/v1/namespaces/${target_ns}/finalize" -f - >/dev/null 2>&1 || true
    }

    # Force-delete stuck pods (the chart's CRDs may block normal deletion)
    for ns in apollo-airlines-apps apollo-airlines-ui apollo-observability; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            echo "  Deleting pods in $ns..."
            while IFS= read -r pod; do
                [[ -n "$pod" ]] || continue
                kubectl delete "$pod" -n "$ns" --force --grace-period=0 2>/dev/null || true
            done < <(kubectl get pods -n "$ns" -o name 2>/dev/null || true)
        fi
    done

    # Namespaces (in order: data plane, then access plane)
    for ns in apollo-airlines-apps apollo-airlines-ui apollo-observability; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            kubectl delete ns "$ns" --ignore-not-found --timeout=60s 2>&1 | tail -2 || finalize_ns "$ns"
        fi
    done

    # Gateway + access stack
    step "Purging Envoy Gateway + MetalLB"
    for ns in envoy-gateway-system metallb-system; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            kubectl delete ns "$ns" --ignore-not-found --timeout=60s 2>&1 | tail -2 || finalize_ns "$ns"
        fi
    done

    # CRDs (cluster-scoped — left behind by helm uninstall sometimes)
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'envoyproxy|gateway\.networking|metallb|monitoring\.coreos' || true); do
        kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
    done

    # Cluster-scoped resources
    kubectl delete gatewayclass eg --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete priorityclass apollo-airlines-app-critical apollo-airlines-app-low --ignore-not-found >/dev/null 2>&1 || true

    # Cluster-scoped RBAC and webhooks from MetalLB, Envoy Gateway, and Prometheus outlive their namespaces
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system --ignore-not-found >/dev/null 2>&1 || true
    for kind in clusterrolebinding clusterrole; do
        for obj in $(kubectl get "$kind" -o name 2>/dev/null | grep -E 'metallb|eg-gateway-helm|apollo-observability|prometheus-operator' || true); do
            kubectl delete "$obj" --ignore-not-found >/dev/null 2>&1 || true
        done
    done

    ok "purge complete"
fi

ok "Stage 6 teardown complete"
