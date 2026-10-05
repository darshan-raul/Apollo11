#!/bin/bash
# Tear down Stage 7 — symmetric to apply.sh.
#
# Usage:
#   ./scripts/teardown.sh                       # helm uninstall (default)
#   ./scripts/teardown.sh --mode kustomize      # kubectl delete -k overlays/dev
#   ./scripts/teardown.sh --purge               # also delete namespaces + cluster-scoped resources
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/context.sh"
apollo_context_guard

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
  --purge       Also delete the app, UI, observability, Envoy Gateway, and
                MetalLB namespaces plus their cluster-scoped resources
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

# Controller bundle deletion includes CRDs even without --purge.
apollo_assert_exclusive_platform

step "Tearing down (mode: $MODE, env: $ENV, purge: $PURGE)"

# Recover any interrupted practical scaling lab before removing its HPA and
# workloads. This also removes the temporary worker label and taint.
if [[ -x "$SCRIPT_DIR/scaling-lab.sh" ]]; then
    "$SCRIPT_DIR/scaling-lab.sh" cleanup >/dev/null 2>&1 || true
fi

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

# Stage 7 installs these dependencies outside the application release so their
# APIs exist before Helm/Kustomize submits HPA/VPA resources. Remove them after
# the workload release to avoid leaving controllers behind.
VPA_BUNDLE="$CHART_DIR/bundles/vpa-install.yaml"
if [[ -f "$VPA_BUNDLE" ]] && kubectl get crd verticalpodautoscalers.autoscaling.k8s.io >/dev/null 2>&1; then
    step "Removing VPA controllers and CRDs"
    kubectl delete -f "$VPA_BUNDLE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    # Clean up the Service emitted by the earlier three-component prototype.
    kubectl delete service vpa-webhook -n kube-system --ignore-not-found >/dev/null 2>&1 || true
fi

METRICS_BUNDLE="$CHART_DIR/bundles/metrics-server-install.yaml"
if [[ -f "$METRICS_BUNDLE" ]]; then
    step "Removing Stage 7 metrics-server"
    kubectl delete -f "$METRICS_BUNDLE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
fi

if [[ "$PURGE" == "true" ]]; then
    step "Purging namespaces + cluster-scoped resources"

    # Force-delete stuck pods (the chart's CRDs may block normal deletion)
    for ns in apollo-airlines-apps apollo-airlines-ui apollo-observability; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            echo "  Patching namespace $ns for force-deletion..."
            kubectl get pods -n "$ns" -o name 2>/dev/null | xargs -r -I{} kubectl --context "$APOLLO_CONTEXT" delete {} -n "$ns" --force --grace-period=0 2>/dev/null || true
        fi
    done

    # Namespaces (in order: data plane, then access plane)
    for ns in apollo-airlines-apps apollo-airlines-ui apollo-observability; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            kubectl delete ns "$ns" --ignore-not-found --timeout 60s 2>&1 | tail -2
        fi
    done

    # Gateway + access stack
    step "Purging Envoy Gateway + MetalLB"
    for ns in envoy-gateway-system metallb-system; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            timeout 60 kubectl --context "$APOLLO_CONTEXT" delete ns "$ns" --ignore-not-found 2>&1 | tail -2 || \
                kubectl patch ns "$ns" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
    done

    # CRDs (cluster-scoped — left behind by helm uninstall sometimes)
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'envoyproxy|gateway\.networking|metallb|monitoring\.coreos|verticalpodautoscaler|autoscaling\.k8s\.io' || true); do
        kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
    done

    # Cluster-scoped resources
    kubectl delete gatewayclass eg --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete priorityclass apollo-airlines-app-critical apollo-airlines-app-low --ignore-not-found >/dev/null 2>&1 || true

    ok "purge complete"
fi

ok "Stage 7 teardown complete"
