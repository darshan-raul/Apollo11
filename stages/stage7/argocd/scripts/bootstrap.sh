#!/bin/bash
# Bootstrap the ArgoCD GitOps module for Stage 7.
#
# What this does:
#   1. Verifies ArgoCD is installed (run ../install.sh first if not)
#   2. Installs Envoy, MetalLB, metrics-server, VPA, the Prometheus Operator,
#      shared platform scheduling/RBAC, and tenant namespaces
#   3. Registers the AppProject in ArgoCD's standard namespace
#   4. Registers 3 isolated tenant Applications plus shared observability
#   5. (optional) requests an immediate dev + staging reconciliation
#
# Idempotent: re-running does not duplicate or break anything.
#
# Usage:
#   ./scripts/bootstrap.sh                       # project + apps, no auto-sync
#   ./scripts/bootstrap.sh --sync                # also force-sync dev + staging
#   ./scripts/bootstrap.sh --sync --include-prod # also force-sync prod (NOT recommended)
#   ./scripts/bootstrap.sh --repo-url URL        # override source.repoURL on all apps
#
# Prerequisites:
#   - kubectl cluster-info works
#   - ArgoCD is installed in the `argocd` namespace (run ../install.sh)
#   - Tenant and observability namespaces do not need to exist; the shared
#     platform manifest creates them before the Applications reconcile.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/context.sh"
apollo_context_guard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$(dirname "$SCRIPT_DIR")"
STAGE_DIR="$(dirname "$ARGOCD_DIR")"
PROJECTS_DIR="$ARGOCD_DIR/projects"
APPS_DIR="$ARGOCD_DIR/applications"
TENANT_NS="argocd"
CHART_DIR="$(dirname "$ARGOCD_DIR")/helm/apollo11"
PLATFORM_FILE="$ARGOCD_DIR/platform/platform.yaml"

SYNC=false
INCLUDE_PROD=false
REPO_URL_OVERRIDE=""
IMAGE_REPOSITORY_OVERRIDE=""

usage() {
    cat <<EOF
Usage: $0 [--sync] [--include-prod] [--repo-url URL] [--image-repository REPO]

Options:
  --sync            After registering the Applications, force-sync dev
                    and staging immediately. Otherwise they'll auto-sync
                    on the next git change.
  --include-prod    Also force-sync prod. NOT recommended outside demos —
                    prod is meant to be human-gated.
  --repo-url URL    Override source.repoURL on all Applications.
                    Default: https://github.com/darshan-raul/Apollo11.git
  --image-repository REPO
                    Override the shared image repository (for example
                    apollo11 when images are preloaded into kind).
  --help            Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --sync)         SYNC=true; shift ;;
        --include-prod) INCLUDE_PROD=true; shift ;;
        --repo-url)     REPO_URL_OVERRIDE="$2"; shift 2 ;;
        --image-repository) IMAGE_REPOSITORY_OVERRIDE="$2"; shift 2 ;;
        --help)         usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/6 Checking cluster + ArgoCD"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
if ! kubectl get ns argocd >/dev/null 2>&1; then
    fail "ArgoCD namespace not found. Run '../install.sh' first."
fi
ok "ArgoCD is installed"

step "1/6 Installing shared Gateway/LoadBalancer/observability platform"
envoy_bundle="$CHART_DIR/bundles/envoy-gateway-install.yaml"
metallb_bundle="$CHART_DIR/bundles/metallb-native.yaml"
operator_bundle="$STAGE_DIR/bundles/prometheus-operator-v0.93.0.yaml"
metrics_bundle="$CHART_DIR/bundles/metrics-server-install.yaml"
vpa_bundle="$CHART_DIR/bundles/vpa-install.yaml"
[[ -f "$envoy_bundle" ]] || fail "missing Envoy Gateway bundle: $envoy_bundle"
[[ -f "$metallb_bundle" ]] || fail "missing MetalLB bundle: $metallb_bundle"
[[ -f "$operator_bundle" ]] || fail "missing Prometheus Operator bundle: $operator_bundle"
[[ -f "$metrics_bundle" ]] || fail "missing metrics-server bundle: $metrics_bundle"
[[ -f "$vpa_bundle" ]] || fail "missing VPA bundle: $vpa_bundle"
[[ -f "$PLATFORM_FILE" ]] || fail "missing platform manifest: $PLATFORM_FILE"
kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply --server-side -f "$envoy_bundle" >/dev/null
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply --server-side --force-conflicts -f "$metallb_bundle" >/dev/null
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s >/dev/null || fail "Gateway API CRDs not established"
kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=60s >/dev/null || fail "MetalLB CRDs not established"
kubectl rollout status deployment/controller -n metallb-system --timeout=120s >/dev/null || fail "MetalLB controller not ready"
kubectl apply -f "$PLATFORM_FILE" >/dev/null
kubectl apply -f "$metrics_bundle" >/dev/null
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s >/dev/null || fail "metrics-server not ready"
kubectl apply --server-side -f "$vpa_bundle" >/dev/null
kubectl wait --for=condition=Established crd/verticalpodautoscalers.autoscaling.k8s.io --timeout=90s >/dev/null || fail "VPA CRD not established"
kubectl rollout status deployment/vpa-recommender -n kube-system --timeout=180s >/dev/null || fail "VPA recommender not ready"
kubectl apply --server-side -f "$operator_bundle" >/dev/null
kubectl wait --for=condition=Established crd/servicemonitors.monitoring.coreos.com --timeout=90s >/dev/null || fail "ServiceMonitor CRD not established"
kubectl rollout status deployment/prometheus-operator -n apollo-observability --timeout=180s >/dev/null || fail "Prometheus Operator not ready"
ok "shared Stage 7 platform, operator, and isolated namespaces ready"

step "2/6 Registering AppProject"
# AppProject must be created BEFORE the Applications, because Applications
# reference it via spec.project.
if [[ -n "$REPO_URL_OVERRIDE" ]]; then
    project_tmp=$(mktemp)
    sed -E "s|https://github.com/darshan-raul/Apollo11(\\.git)?|$REPO_URL_OVERRIDE|" \
        "$PROJECTS_DIR/project.yaml" > "$project_tmp"
    kubectl apply -f "$project_tmp" 2>&1 | tail -2
    rm -f "$project_tmp"
else
    kubectl apply -f "$PROJECTS_DIR/project.yaml" 2>&1 | tail -2
fi
ok "AppProject apollo-airlines"

step "3/6 Registering Applications"
for app_yaml in "$APPS_DIR"/*.yaml; do
    name=$(basename "$app_yaml" .yaml)
    if [[ -n "$REPO_URL_OVERRIDE" || -n "$IMAGE_REPOSITORY_OVERRIDE" ]]; then
        tmp=$(mktemp)
        cp "$app_yaml" "$tmp"
        if [[ -n "$REPO_URL_OVERRIDE" ]]; then
            sed -i -E "s|repoURL: https://github.com/darshan-raul/Apollo11(\\.git)?|repoURL: $REPO_URL_OVERRIDE|" "$tmp"
        fi
        if [[ -n "$IMAGE_REPOSITORY_OVERRIDE" ]]; then
            sed -i "s|value: ghcr.io/darshan-raul/apollo11|value: $IMAGE_REPOSITORY_OVERRIDE|" "$tmp"
        fi
        kubectl apply -f "$tmp" 2>&1 | tail -1
        rm -f "$tmp"
    else
        kubectl apply -f "$app_yaml" 2>&1 | tail -1
    fi
    ok "Application $name"
done

step "4/6 Waiting for ArgoCD to pick up the new Applications"
# ArgoCD's app-controller refreshes every 3s by default. We poll the
# resource tree (status.resources) which only gets populated after
# the first reconciliation.
for app in apollo11-dev apollo11-staging apollo11-prod apollo11-observability; do
    for i in $(seq 1 15); do
        # application_controller is the label selector for the controller pod
        # (not the application itself). We just wait for the App CR to have
        # an observedGeneration matching its metadata.generation.
        reconciled=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.status.reconciledAt}' 2>/dev/null || echo "")
        if [[ -n "$reconciled" ]]; then
            ok "$app reconciled at $reconciled"
            break
        fi
        sleep 2
    done
done

if [[ "$SYNC" == "true" ]]; then
    step "5/6 Force-syncing dev + staging"
    kubectl annotate application apollo11-dev -n "$TENANT_NS" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
    kubectl annotate application apollo11-staging -n "$TENANT_NS" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
    kubectl annotate application apollo11-observability -n "$TENANT_NS" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
    if [[ "$INCLUDE_PROD" == "true" ]]; then
        echo "  (--include-prod only refreshes prod; prod remains manual-sync)"
        kubectl annotate application apollo11-prod -n "$TENANT_NS" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
    fi
    ok "hard refresh requested"
else
    step "5/6 Skipping force-sync (run with --sync to force)"
fi

step "6/6 Summary"
echo ""
echo "  Applications registered in namespace '$TENANT_NS':"
kubectl get applications -n "$TENANT_NS" --no-headers 2>/dev/null | awk '{print "    " $1}'
echo ""
echo "  Next steps:"
echo "    1. Watch:        kubectl get applications -n $TENANT_NS -w"
echo "    2. Open the UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "                     open http://localhost:8080"
echo "    3. Verify:       bash scripts/verify.sh"
echo ""
ok "Bootstrap complete"
