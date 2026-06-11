#!/bin/bash
# Tear down Stage 6 — symmetric to apply.sh.
#
# Three levels of teardown:
#   (default)  Delete the helm release + remove the observability namespace
#              (apps + access stack stay, but observability stack + Grafana route
#              go away). Add --full to delete the data plane too.
#   --full     Also delete the 2 app namespaces + access stack
#   --purge    --full + delete cluster-scoped CRDs
#
# Usage:
#   ./scripts/teardown.sh
#   ./scripts/teardown.sh --full
#   ./scripts/teardown.sh --purge

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"
RELEASE_NAME="apollo11"
ARGOCD_NS="argocd"

MODE="apps"  # apps | full | purge

usage() {
    cat <<EOF
Usage: $0 [--full | --purge]

Options:
  (default)  Delete helm release + observability namespace.
  --full     Also delete the 2 app namespaces + access stack.
  --purge    --full + delete cluster-scoped CRDs (Envoy, MetalLB).
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
kubectl cluster-info >/dev/null 2>&1 || fail "kubectl cannot reach a cluster"
ok "cluster reachable"

# ----------------------------------------------------------------------------
# 1. Observability stack (always)
# ----------------------------------------------------------------------------
step "1/3 Removing observability stack"
if kubectl get ns apollo-observability >/dev/null 2>&1; then
    # Delete in reverse dependency order: ServiceMonitors first, then the
    # workloads that reference them, then the namespace.
    for app in identity flight booking search notification; do
        kubectl delete -f "$CHART_DIR/templates/observability/servicemonitors/${app}-sm.yaml" \
            --ignore-not-found 2>&1 | tail -1 || true
    done
    kubectl delete -f "$CHART_DIR/templates/observability/ingress/grafana-route.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    kubectl delete -f "$CHART_DIR/templates/observability/loki/deployment.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    kubectl delete -f "$CHART_DIR/templates/observability/grafana/deployment.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    kubectl delete -f "$CHART_DIR/templates/observability/prometheus/deployment.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    kubectl delete -f "$CHART_DIR/templates/observability/tempo/deployment.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    kubectl delete -f "$CHART_DIR/templates/observability/otel-collector/daemonset.yaml" \
        --ignore-not-found 2>&1 | tail -1 || true
    # Now the namespace itself
    kubectl delete ns apollo-observability --ignore-not-found --timeout=120s 2>&1 | tail -1
    ok "observability namespace removed"
else
    echo "  (skip) observability namespace not present"
fi

# ----------------------------------------------------------------------------
# 2. App stack (full | purge)
# ----------------------------------------------------------------------------
if [[ "$MODE" == "full" || "$MODE" == "purge" ]]; then
    step "2/3 Removing helm release + app namespaces"
    if helm list -n apollo-airlines-apps 2>/dev/null | grep -q "$RELEASE_NAME"; then
        helm uninstall "$RELEASE_NAME" -n apollo-airlines-apps --wait --timeout 5m 2>&1 | tail -2
        ok "helm uninstall complete"
    else
        echo "  (skip) helm release not found"
    fi
    for ns in apollo-airlines-apps apollo-airlines-ui; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            # Force-delete stuck pods
            kubectl get pods -n "$ns" -o name 2>/dev/null | \
                xargs -r -I{} kubectl delete {} -n "$ns" --force --grace-period=0 2>/dev/null || true
            kubectl delete ns "$ns" --ignore-not-found --timeout 60s 2>&1 | tail -1
        fi
    done
    ok "app namespaces removed"
else
    step "2/3 Skipping (run with --full or --purge)"
fi

# ----------------------------------------------------------------------------
# 3. Access stack (purge only)
# ----------------------------------------------------------------------------
if [[ "$MODE" == "purge" ]]; then
    step "3/3 Removing access stack (Envoy + MetalLB)"
    for ns in envoy-gateway-system metallb-system; do
        if kubectl get ns "$ns" >/dev/null 2>&1; then
            kubectl get pods -n "$ns" -o name 2>/dev/null | \
                xargs -r -I{} kubectl delete {} -n "$ns" --force --grace-period=0 2>/dev/null || true
            timeout 60 kubectl delete ns "$ns" --ignore-not-found 2>&1 | tail -1 || \
                kubectl patch ns "$ns" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
    done
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'envoyproxy|gateway\.networking|metallb' || true); do
        kubectl delete "$crd" --ignore-not-found 2>&1 | tail -1
    done
    ok "access stack purged"
else
    step "3/3 Skipping (run with --purge to remove access stack)"
fi

ok "Stage 6 teardown complete (mode: $MODE)"
