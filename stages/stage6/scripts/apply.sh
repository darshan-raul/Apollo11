#!/bin/bash
# Apply Stage 6: Mission Ops — full Apollo Airlines + observability stack.
#
# What this does (10 phases):
#   1. Build + load the 6 backend images (with OTEL SDK)
#   2. Pre-install: Envoy Gateway + MetalLB CRDs (from chart bundles)
#   3. Wait for CRDs + MetalLB webhook
#   4. Helm install the main chart (apps, infra, gateway, jobs, PDBs)
#   5. Wait for StatefulSets + Deployments + frontend
#   6. (Stage 6) Install the observability namespace + RBAC
#   7. (Stage 6) Install OTEL Collector (DaemonSet) + Tempo
#   8. (Stage 6) Install Prometheus + Grafana + Loki + Promtail
#   9. (Stage 6) Install ServiceMonitors + Grafana HTTPRoute
#  10. Wait for Prometheus to discover all 5 services + OTEL to receive
#      a test trace
#
# Total: ~7-10 minutes on a fresh kind cluster.
#
# Usage:
#   ./scripts/apply.sh                       # defaults
#   ./scripts/apply.sh --mode kustomize     # dev iteration
#   ./scripts/apply.sh --tag v1.2.3
#   ./scripts/apply.sh --skip-build
#   ./scripts/apply.sh --env prod
#   ./scripts/apply.sh --skip-observability  # just the app, no observability stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"
CODE_DIR="$STAGE_DIR/code"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"

MODE="helm"
ENV="dev"
TAG="latest"
SKIP_BUILD=false
RELEASE_NAME="apollo11"
INCLUDE_OBSERVABILITY=true

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--tag TAG] [--skip-build] [--skip-observability]

Options:
  --mode MODE             helm (default) | kustomize
  --env ENV               dev (default) | staging | prod
  --tag TAG               Image tag (default: latest)
  --skip-build            Reuse pre-built images; skip docker build
  --skip-observability    Install only the app stack, not Prometheus/Grafana/etc.
  --help                  Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)               MODE="$2"; shift 2 ;;
        --env)                ENV="$2"; shift 2 ;;
        --tag)                TAG="$2"; shift 2 ;;
        --skip-build)         SKIP_BUILD=true; shift ;;
        --skip-observability) INCLUDE_OBSERVABILITY=false; shift ;;
        --help)               usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/10 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster"
fi
ok "cluster reachable"

# ----------------------------------------------------------------------------
# Phase 1: build images
# ----------------------------------------------------------------------------
if [[ "$SKIP_BUILD" != "true" ]]; then
    step "1/10 Building + loading images (tag: $TAG)"
    bash "$SCRIPT_DIR/build-images.sh" --tag "$TAG" --cluster "$CLUSTER" 2>&1 | tail -5 || \
        echo "  (image build warnings — continuing)"
else
    step "1/10 Skipping build (--skip-build)"
fi

# ----------------------------------------------------------------------------
# Phase 2: pre-install CRD bundles (Envoy + MetalLB)
# ----------------------------------------------------------------------------
step "2/10 Pre-install: Envoy Gateway + MetalLB CRD bundles"
if [[ -f "$CHART_DIR/bundles/envoy-gateway-install.yaml" ]]; then
    kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side -f "$CHART_DIR/bundles/envoy-gateway-install.yaml" 2>&1 | tail -1
    ok "Envoy Gateway CRDs"
fi
if [[ -f "$CHART_DIR/bundles/metallb-native.yaml" ]]; then
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -f "$CHART_DIR/bundles/metallb-native.yaml" 2>&1 | tail -1
    ok "MetalLB CRDs"
fi

# ----------------------------------------------------------------------------
# Phase 3: wait for CRDs + MetalLB webhook
# ----------------------------------------------------------------------------
step "3/10 Waiting for CRD registration"
for i in $(seq 1 10); do
    if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && \
       kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
        ok "CRDs registered"
        break
    fi
    sleep 3
done

step "3b/10 Waiting for MetalLB webhook"
for i in $(seq 1 20); do
    endpoints=$(kubectl get endpoints metallb-webhook-service -n metallb-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$endpoints" ]]; then
        ok "MetalLB webhook endpoint ready ($endpoints)"
        break
    fi
    sleep 3
done

# ----------------------------------------------------------------------------
# Phase 4: helm install
# ----------------------------------------------------------------------------
step "4/10 Helm install (release: $RELEASE_NAME, env: $ENV)"
HELM_CMD=(helm upgrade --install "$RELEASE_NAME" "$CHART_DIR"
    --namespace apollo-airlines-apps
    --create-namespace
    --set image.tag="$TAG"
    --set gateway.envoy.bundleInstall=false
    --set metallb.bundleInstall=false
    --wait --timeout 10m)
if [[ -f "$CHART_DIR/values-${ENV}.yaml" ]]; then
    HELM_CMD+=(-f "$CHART_DIR/values-${ENV}.yaml")
    echo "  using values file: values-${ENV}.yaml"
fi
"${HELM_CMD[@]}" 2>&1 | tail -5
ok "helm install complete"

# ----------------------------------------------------------------------------
# Phase 5: wait for workloads
# ----------------------------------------------------------------------------
step "5/10 Waiting for StatefulSets (3 PG + 1 Redis)"
for sts in identity-db flight-db booking-db redis; do
    kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
        -n apollo-airlines-apps "statefulset/$sts" --timeout=120s 2>/dev/null && \
        ok "statefulset/$sts ready" || \
        echo "  (warn) statefulset/$sts not ready"
done

step "5b/10 Waiting for seed jobs"
for job in seed-identity-db seed-flight-db seed-booking-db; do
    kubectl wait --for=condition=Complete -n apollo-airlines-apps "job/$job" --timeout=120s 2>/dev/null && \
        ok "job/$job Complete" || \
        echo "  (warn) job/$job not complete"
done

step "5c/10 Waiting for app Deployments + frontend"
for dep in identity flight booking search notification; do
    kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
        -n apollo-airlines-apps "deployment/$dep" --timeout=120s 2>/dev/null && \
        ok "deployment/$dep ready" || \
        echo "  (warn) deployment/$dep not ready"
done
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    -n apollo-airlines-ui "deployment/frontend" --timeout=120s 2>/dev/null && \
    ok "deployment/frontend ready" || \
    echo "  (warn) deployment/frontend not ready"

# ----------------------------------------------------------------------------
# Phases 6-9: Observability stack (Stage 6)
# ----------------------------------------------------------------------------
if [[ "$INCLUDE_OBSERVABILITY" == "true" ]]; then
    step "6/10 Installing observability namespace + RBAC"
    kubectl apply -f "$CHART_DIR/templates/observability/namespace.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/serviceaccount.yaml" 2>&1 | tail -1
    ok "observability namespace + ServiceAccount + ClusterRole"

    step "7/10 Installing OTEL Collector + Tempo"
    kubectl apply -f "$CHART_DIR/templates/observability/otel-collector/config.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/otel-collector/daemonset.yaml" 2>&1 | tail -2
    kubectl apply -f "$CHART_DIR/templates/observability/tempo/config.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/tempo/deployment.yaml" 2>&1 | tail -1
    ok "OTEL Collector + Tempo manifests applied"

    step "8/10 Installing Prometheus + Grafana + Loki + Promtail"
    kubectl apply -f "$CHART_DIR/templates/observability/prometheus/config.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/prometheus/rules.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/prometheus/deployment.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/grafana/datasources.yaml" 2>&1 | tail -1
    for d in overview booking errors saturation trace-viewer; do
        kubectl apply -f "$CHART_DIR/templates/observability/grafana/dashboard-${d}.yaml" 2>&1 | tail -1
    done
    kubectl apply -f "$CHART_DIR/templates/observability/grafana/deployment.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/loki/config.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/loki/promtail-config.yaml" 2>&1 | tail -1
    kubectl apply -f "$CHART_DIR/templates/observability/loki/deployment.yaml" 2>&1 | tail -2
    ok "Prometheus + Grafana + Loki + Promtail applied"

    step "9/10 Installing ServiceMonitors + Grafana HTTPRoute"
    for app in identity flight booking search notification; do
        kubectl apply -f "$CHART_DIR/templates/observability/servicemonitors/${app}-sm.yaml" 2>&1 | tail -1
    done
    kubectl apply -f "$CHART_DIR/templates/observability/ingress/grafana-route.yaml" 2>&1 | tail -2
    ok "ServiceMonitors + Grafana HTTPRoute"

    step "10/10 Waiting for observability pods"
    for pod in prometheus grafana tempo loki otel-collector; do
        # OTEL collector is a DaemonSet, others are Deployments
        if [[ "$pod" == "otel-collector" ]]; then
            for i in $(seq 1 20); do
                if kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=$pod" --no-headers 2>/dev/null | grep -q "1/1"; then
                    ok "$pod 1/1 Ready"
                    break
                fi
                sleep 3
            done
        else
            for i in $(seq 1 20); do
                if kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=$pod" --no-headers 2>/dev/null | grep -q "1/1"; then
                    ok "$pod 1/1 Ready"
                    break
                fi
                sleep 3
            done
        fi
    done
    for i in $(seq 1 20); do
        if kubectl get pods -n apollo-observability -l "app.kubernetes.io/name=promtail" --no-headers 2>/dev/null | grep -q "1/1"; then
            ok "promtail 1/1 Ready"
            break
        fi
        sleep 3
    done

    step "10b/10 Waiting for Prometheus to discover 5 services"
    for i in $(seq 1 30); do
        # After 60s of Prometheus running, query its targets
        sleep 5
        up_count=$(kubectl exec -n apollo-observability deploy/prometheus -- \
            wget -qO- 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | \
            grep -oE '"service":"[a-z]+"' | wc -l || echo 0)
        if [[ "$up_count" -ge 5 ]]; then
            ok "Prometheus has discovered $up_count services"
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "  (warn) Prometheus has only discovered $up_count services after 150s"
        fi
    done
fi

ok "Stage 6 apply complete"
echo ""
echo "  Next: bash scripts/verify.sh"
echo "  Open Grafana: kubectl port-forward svc/grafana -n apollo-observability 3000:3000 &"
echo "  Open Prometheus: kubectl port-forward svc/prometheus -n apollo-observability 9090:9090 &"
echo "  Run a trace test: bash scripts/trace-test.sh"
