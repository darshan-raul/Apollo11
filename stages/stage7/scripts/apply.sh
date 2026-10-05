#!/bin/bash
# Apply Stage 7: Apollo Airlines observability plus autoscaling, scheduling,
# and Redis-backed search caching. Supports Helm and Kustomize delivery paths.
#
# Modes:
#   helm      — single `helm install` provisions the full cluster:
#                 * 3 namespaces (apps, ui, observability)
#                 * 13 ServiceAccounts
#                 * 3 Postgres StatefulSets + headless SVCs + init ConfigMaps
#                 * 1 Redis StatefulSet + headless SVC
#                 * 6 app Deployments + 1 frontend Deployment
#                 * 2 PodDisruptionBudgets (booking, frontend)
#                 * 3 idempotent seed Jobs
#                 * Envoy Gateway install + GatewayClass + Gateway
#                 * 7 HTTPRoutes + cross-namespace ReferenceGrants
#                 * MetalLB install + IPAddressPool + L2Advertisement
#                 * Prometheus Operator, Prometheus, Grafana, Tempo, Loki,
#                   OTEL Collector, Alloy, ServiceMonitors, and alert rules
#
#   kustomize — installs the prerequisite controller bundles, then applies the
#               full committed plain-manifest base through overlays/{env}/.
#               Helm is not used by this path.
#
# Usage:
#   ./scripts/apply.sh                                  # helm install with defaults
#   ./scripts/apply.sh --mode kustomize --env dev       # kustomize dev overlay
#   ./scripts/apply.sh --env staging                    # helm with values-staging.yaml
#   ./scripts/apply.sh --env prod --tag v1.2.3          # helm with values-prod.yaml + tag
#   ./scripts/apply.sh --skip-build
#   ./scripts/apply.sh --tag v1.2.3
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"
CODE_DIR="$STAGE_DIR/code"
CLUSTER="${CLUSTER:-}"
REGISTRY="apollo11"

MODE="helm"
ENV="dev"
TAG="latest"
TAG_EXPLICIT=false
SKIP_BUILD=false
RELEASE_NAME="apollo11"
OBSERVABILITY_ENABLED=true

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--tag TAG] [--skip-build] [--without-observability] [--release NAME]

Options:
  --mode MODE       helm (default) | kustomize
  --env ENV         dev (default) | staging | prod
                    helm mode:      picks helm/apollo11/values-\$ENV.yaml
                    kustomize mode: picks overlays/\$ENV/
  --tag TAG         Helm image-tag override (default: latest). Kustomize tags
                    are declared by the selected overlay and must match.
  --skip-build      Reuse pre-built images; skip the docker build step
  --without-observability  Install only the trusted Stage 5-compatible baseline
  --release NAME    Helm release name (default: apollo11)
  --help            Show this help

Examples:
  $0                                          # helm install (defaults: tag=latest, no env file)
  $0 --env dev                                # helm with values-dev.yaml (1 replica, tag=latest)
  $0 --env staging --tag latest               # helm with values-staging.yaml
  $0 --env prod --tag v1.2.3                  # helm with values-prod.yaml
  $0 --mode kustomize --env dev               # kustomize overlays/dev/
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)        MODE="$2"; shift 2 ;;
        --env)         ENV="$2"; shift 2 ;;
        --tag)         TAG="$2"; TAG_EXPLICIT=true; shift 2 ;;
        --skip-build)  SKIP_BUILD=true; shift ;;
        --without-observability) OBSERVABILITY_ENABLED=false; shift ;;
        --release)     RELEASE_NAME="$2"; shift 2 ;;
        --cluster)     CLUSTER="$2"; shift 2 ;;
        --help)        usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

source "${SCRIPT_DIR}/context.sh"
apollo_context_guard
if [[ -n "$CLUSTER" && "kind-$CLUSTER" != "$APOLLO_CONTEXT" ]]; then
    echo "Cluster $CLUSTER does not match context $APOLLO_CONTEXT" >&2
    exit 2
fi
CLUSTER="${APOLLO_CONTEXT#kind-}"


# Validate env early so a typo doesn't surface mid-install
case "$ENV" in
    dev|staging|prod) ;;
    *) echo "Invalid --env '$ENV' (expected dev, staging, or prod)"; usage ;;
esac
case "$MODE" in
    helm|kustomize) ;;
    *) echo "Invalid --mode '$MODE' (expected helm or kustomize)"; usage ;;
esac

if [[ "$MODE" == "kustomize" ]]; then
    if [[ "$ENV" == "prod" ]]; then
        expected_tag="v1.0.0"
        # Production references immutable GHCR images; there is no useful
        # local kind image to build or load for this overlay.
        SKIP_BUILD=true
    else
        expected_tag="latest"
    fi
    if [[ "$TAG_EXPLICIT" == "true" && "$TAG" != "$expected_tag" ]]; then
        echo "Kustomize overlay '$ENV' declares image tag '$expected_tag', not '$TAG'."
        exit 1
    fi
    TAG="$expected_tag"
fi

# Colors
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

install_platform_bundles() {
    local envoy_bundle="$CHART_DIR/bundles/envoy-gateway-install.yaml"
    local metallb_bundle="$CHART_DIR/bundles/metallb-native.yaml"
    local crds_ready=false
    local endpoints=""

    [[ -f "$envoy_bundle" ]] || fail "missing Envoy Gateway bundle: $envoy_bundle"
    [[ -f "$metallb_bundle" ]] || fail "missing MetalLB bundle: $metallb_bundle"

    kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side -f "$envoy_bundle" 2>&1 | tail -2
    ok "Envoy Gateway bundle applied"

    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -f "$metallb_bundle" 2>&1 | tail -2
    ok "MetalLB bundle applied"

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && \
           kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
            crds_ready=true
            break
        fi
        sleep 3
    done
    [[ "$crds_ready" == "true" ]] || fail "Envoy Gateway/MetalLB CRDs did not register within 30s"
    ok "platform CRDs registered"

    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        endpoints=$(kubectl get endpoints metallb-webhook-service -n metallb-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        [[ -n "$endpoints" ]] && break
        sleep 3
    done
    [[ -n "$endpoints" ]] || fail "MetalLB webhook did not become ready within 60s"
    ok "MetalLB webhook endpoint ready ($endpoints)"
}

install_observability_operator() {
    local operator_bundle="$STAGE_DIR/bundles/prometheus-operator-v0.93.0.yaml"
    [[ -f "$operator_bundle" ]] || fail "missing Prometheus Operator bundle: $operator_bundle"
    kubectl create namespace apollo-observability --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -f "$operator_bundle" >/dev/null
    kubectl wait --for=condition=Established crd/prometheuses.monitoring.coreos.com --timeout=90s >/dev/null || \
        fail "Prometheus CRD did not become Established"
    kubectl rollout status deployment/prometheus-operator -n apollo-observability --timeout=180s >/dev/null || \
        fail "Prometheus Operator did not become ready"
    ok "Prometheus Operator v0.93.0 ready"
}

install_stage7_dependencies() {
    local metrics_bundle="$CHART_DIR/bundles/metrics-server-install.yaml"
    local vpa_bundle="$CHART_DIR/bundles/vpa-install.yaml"

    [[ -f "$metrics_bundle" ]] || fail "missing metrics-server bundle: $metrics_bundle"
    kubectl apply -f "$metrics_bundle" >/dev/null
    kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s >/dev/null || \
        fail "metrics-server did not become ready"
    ok "metrics-server ready"

    # Dev intentionally omits VPA's three control-plane pods. Staging and
    # production install VPA before the chart submits the search VPA resource,
    # so API discovery is complete when Helm/Kustomize applies it.
    if [[ "$ENV" != "dev" ]]; then
        [[ -f "$vpa_bundle" ]] || fail "missing VPA bundle: $vpa_bundle"
        kubectl apply --server-side -f "$vpa_bundle" >/dev/null
        kubectl wait --for=condition=Established \
            crd/verticalpodautoscalers.autoscaling.k8s.io --timeout=90s >/dev/null || \
            fail "VPA CRD did not become Established"
        for dep in vpa-recommender vpa-updater; do
            kubectl rollout status -n kube-system "deployment/$dep" --timeout=180s >/dev/null || \
                fail "deployment/$dep did not become ready"
            ok "deployment/$dep ready"
        done
    fi
}

wait_stage7() {
    step "Waiting for Stage 7 autoscaling resources"

    metrics_ready=false
    for _ in $(seq 1 24); do
        if kubectl top nodes >/dev/null 2>&1; then
            metrics_ready=true
            break
        fi
        sleep 5
    done
    [[ "$metrics_ready" == "true" ]] || fail "metrics.k8s.io did not return node data within 120s"
    ok "metrics.k8s.io returns node data"

    kubectl get hpa search-hpa -n apollo-airlines-apps >/dev/null 2>&1 || \
        fail "hpa/search-hpa is missing"
    hpa_ready=false
    for _ in $(seq 1 20); do
        current_cpu=$(kubectl get hpa search-hpa -n apollo-airlines-apps \
            -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo "")
        if [[ -n "$current_cpu" ]]; then
            hpa_ready=true
            break
        fi
        sleep 3
    done
    [[ "$hpa_ready" == "true" ]] || fail "search HPA did not populate its CPU target within 60s"
    ok "search HPA reports current CPU utilization"

    if [[ "$ENV" != "dev" ]]; then
        kubectl get vpa search-vpa -n apollo-airlines-apps >/dev/null 2>&1 || \
            fail "vpa/search-vpa is missing"
        ok "search VPA exists in recommendation-only mode"
    fi
}

wait_observability() {
    [[ "$OBSERVABILITY_ENABLED" == "true" ]] || return 0
    step "Waiting for Stage 6 observability workloads"
    for dep in grafana loki tempo; do
        kubectl rollout status -n apollo-observability "deployment/$dep" --timeout=240s >/dev/null || \
            fail "deployment/$dep did not become ready"
        ok "deployment/$dep ready"
    done
    for ds in otel-collector alloy; do
        kubectl rollout status -n apollo-observability "daemonset/$ds" --timeout=240s >/dev/null || \
            fail "daemonset/$ds did not become ready"
        ok "daemonset/$ds ready"
    done
    kubectl rollout status -n apollo-observability statefulset/prometheus-apollo --timeout=240s >/dev/null || \
        fail "Prometheus StatefulSet did not become ready"
    ok "statefulset/prometheus-apollo ready"
}

step "0/9 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
ok "cluster reachable"

# ---------------------------------------------------------------------------
# Phase 1: build + load images
# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" != "true" ]]; then
    step "1/8 Building + loading images (tag: $TAG)"
    bash "$SCRIPT_DIR/build-images.sh" --tag "$TAG" --cluster "$CLUSTER"
    ok "all 6 application images built and loaded"
else
    step "1/8 Skipping build (--skip-build)"
fi

# ---------------------------------------------------------------------------
# Phase 2: mode-specific apply
# ---------------------------------------------------------------------------
if [[ "$MODE" == "helm" ]]; then
    # ---------------------------------------------------------------------
    # Helm: full one-shot install
    # ---------------------------------------------------------------------
    # The chart bundles the Envoy Gateway + MetalLB install manifests.
    # These need to be applied BEFORE `helm install` because the chart
    # creates GatewayClass / IPAddressPool / L2Advertisement / HTTPRoute
    # resources that depend on the CRDs. If we install them in the same
    # transaction as those custom resources, the API server hasn't
    # registered the CRDs yet and we get "no matches for kind" errors.
    step "2/9 Pre-install: CRD bundles and Stage 7 metrics dependencies"
    # Both bundles use --server-side for the >256KB last-applied-config
    # workaround. MetalLB needs --force-conflicts because its webhook
    # manages its own CA.
    ENVOY_BUNDLE="$CHART_DIR/bundles/envoy-gateway-install.yaml"
    METALLB_BUNDLE="$CHART_DIR/bundles/metallb-native.yaml"
    [[ -f "$ENVOY_BUNDLE" ]] || fail "missing Envoy Gateway bundle: $ENVOY_BUNDLE"
    [[ -f "$METALLB_BUNDLE" ]] || fail "missing MetalLB bundle: $METALLB_BUNDLE"

    kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side -f "$ENVOY_BUNDLE" 2>&1 | tail -2
    ok "Envoy Gateway bundle applied"

    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -f "$METALLB_BUNDLE" 2>&1 | tail -2
    ok "MetalLB bundle applied"

    if [[ "$OBSERVABILITY_ENABLED" == "true" ]]; then
        install_observability_operator
    fi
    install_stage7_dependencies

    step "3/8 Wait for CRD registration"
    # Wait until the API server can see the new CRDs
    crds_ready=false
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && \
           kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
            ok "CRDs registered"
            crds_ready=true
            break
        fi
        sleep 3
    done
    [[ "$crds_ready" == "true" ]] || fail "Envoy Gateway/MetalLB CRDs did not register within 30s"

    step "4/8 Wait for MetalLB webhook to be ready"
    # The MetalLB IPAddressPool has a validating webhook. The webhook
    # service must be up before the chart can create pool resources.
    endpoints=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        # Webhook endpoints become non-empty when the controller pod is up
        endpoints=$(kubectl get endpoints metallb-webhook-service -n metallb-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$endpoints" ]]; then
            ok "MetalLB webhook endpoint ready ($endpoints)"
            break
        fi
        sleep 3
    done
    [[ -n "$endpoints" ]] || fail "MetalLB webhook did not become ready within 60s"

    step "5/8 Helm install (release: $RELEASE_NAME, env: $ENV)"
    # Helm's release namespace is created by --create-namespace. The chart
    # deliberately owns neither namespace, so create the cross-namespace UI
    # target before Helm submits its resources.
    kubectl create namespace apollo-airlines-ui --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl create namespace apollo-airlines-apps --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    bash "$SCRIPT_DIR/generate-certs.sh" --context "$APOLLO_CONTEXT"
    HELM_CMD=(helm upgrade --install "$RELEASE_NAME" "$CHART_DIR"
        --namespace apollo-airlines-apps
        --create-namespace
        --set image.tag="$TAG"
        --set gateway.envoy.bundleInstall=false
        --set metallb.bundleInstall=false
        --set autoscaling.metricsServer.bundleInstall=false
        --set vpa.bundleInstall=false
        --set observability.enabled="$OBSERVABILITY_ENABLED"
        --wait --wait-for-jobs --timeout 10m)

    # Apply env-specific values file if present (values-dev.yaml,
    # values-staging.yaml, values-prod.yaml). The env-specific file
    # overrides values.yaml defaults; --set image.tag still wins for
    # the tag, so CLI override beats the env file.
    if [[ "$ENV" != "dev" ]] || [[ -f "$CHART_DIR/values-${ENV}.yaml" ]]; then
        VALUES_FILE="$CHART_DIR/values-${ENV}.yaml"
        if [[ -f "$VALUES_FILE" ]]; then
            HELM_CMD+=(-f "$VALUES_FILE")
            echo "  using values file: $VALUES_FILE"
        fi
    fi

    "${HELM_CMD[@]}" 2>&1 | tail -20
    ok "helm install complete"

    step "6/8 Waiting for MetalLB controller pod"
    metallb_ready=false
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if kubectl get pods -n metallb-system -l component=controller --no-headers 2>/dev/null | grep -q "1/1"; then
            ok "MetalLB controller ready"
            metallb_ready=true
            break
        fi
        sleep 5
    done
    [[ "$metallb_ready" == "true" ]] || fail "MetalLB controller did not become ready within 75s"

    step "7/8 Waiting for Envoy Gateway"
    # The Envoy data-plane pod has two containers in the bundled release.
    # Check the Pod Ready condition instead of assuming a literal 1/1 count.
    kubectl wait --for=condition=Ready pod \
        -n envoy-gateway-system \
        -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
        --timeout=100s >/dev/null || fail "Envoy data-plane pod did not become ready within 100s"
    ok "Envoy Gateway ready"

    step "8/8 Waiting for StatefulSets (3 PG + 1 Redis)"
    for sts in identity-db flight-db booking-db redis; do
        kubectl rollout status -n apollo-airlines-apps "statefulset/$sts" --timeout=180s >/dev/null || \
            fail "statefulset/$sts did not become ready"
        ok "statefulset/$sts ready"
    done

    step "8b/8 Waiting for seed jobs"
    for job in seed-identity-db seed-flight-db seed-booking-db; do
        kubectl wait --for=condition=Complete -n apollo-airlines-apps "job/$job" --timeout=120s >/dev/null || \
            fail "job/$job did not complete"
        ok "job/$job Complete"
    done

    step "8c/8 Waiting for app Deployments (5 backends + frontend)"
    for dep in identity flight booking search notification; do
        kubectl rollout status -n apollo-airlines-apps "deployment/$dep" --timeout=180s >/dev/null || \
            fail "deployment/$dep did not become ready"
        ok "deployment/$dep ready"
    done
    kubectl rollout status -n apollo-airlines-ui deployment/frontend --timeout=180s >/dev/null || \
        fail "deployment/frontend did not become ready"
    ok "deployment/frontend ready"

    wait_stage7
    wait_observability

    step "8/8 Summary"
    ok "Apollo Airlines Stage 7 installed via Helm"
    echo "  Run 'bash scripts/verify.sh --mode helm' to run the verify suite"
    echo "  Run 'bash scripts/scaling-lab.sh' for the practical HPA + scheduling lab"
    echo "  Run 'bash scripts/teardown.sh --mode helm' to uninstall"

elif [[ "$MODE" == "kustomize" ]]; then
    # ---------------------------------------------------------------------
    # Kustomize: plain manifest base + dev/staging/prod overlay
    # ---------------------------------------------------------------------
    OVERLAY_DIR="$STAGE_DIR/overlays/$ENV"
    if [[ ! -d "$OVERLAY_DIR" ]]; then
        fail "overlay dir not found: $OVERLAY_DIR (env: $ENV)"
    fi

    step "2/8 Installing Envoy Gateway + MetalLB controller bundles"
    install_platform_bundles
    if [[ "$OBSERVABILITY_ENABLED" == "true" ]]; then
        install_observability_operator
    fi
    install_stage7_dependencies

    step "3/8 Ensuring workload namespaces exist"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: apollo-airlines-apps
  labels:
    app.kubernetes.io/part-of: apollo-airlines
    app.kubernetes.io/component: apps
---
apiVersion: v1
kind: Namespace
metadata:
  name: apollo-airlines-ui
  labels:
    app.kubernetes.io/part-of: apollo-airlines
    app.kubernetes.io/component: ui
EOF
    ok "namespaces ready"
    bash "$SCRIPT_DIR/generate-certs.sh" --context "$APOLLO_CONTEXT"

    step "4/8 Kustomize build ($ENV overlay)"
    echo "  Building kustomize overlay at $OVERLAY_DIR..."
    rendered_manifest=$(mktemp)
    render_errors=$(mktemp)
    if ! kubectl kustomize "$OVERLAY_DIR" > "$rendered_manifest" 2>"$render_errors"; then
        cat "$render_errors"
        rm -f "$rendered_manifest" "$render_errors"
        fail "kustomize build failed"
    fi
    rm -f "$render_errors"
    ok "kustomize build OK ($(wc -l < "$rendered_manifest") lines)"

    step "5/8 Applying complete plain-manifest overlay"
    kubectl apply -f "$rendered_manifest"
    rm -f "$rendered_manifest"
    ok "kustomize overlay applied"

    step "6/8 Waiting for StatefulSets + seed Jobs"
    for sts in identity-db flight-db booking-db redis; do
        kubectl rollout status -n apollo-airlines-apps "statefulset/$sts" --timeout=180s >/dev/null || fail "statefulset/$sts did not become ready"
        ok "statefulset/$sts ready"
    done
    for job in seed-identity-db seed-flight-db seed-booking-db; do
        kubectl wait --for=condition=Complete -n apollo-airlines-apps "job/$job" --timeout=120s >/dev/null || fail "job/$job did not complete"
        ok "job/$job Complete"
    done

    step "7/8 Waiting for application Deployments"
    for dep in identity flight booking search notification; do
        kubectl rollout status -n apollo-airlines-apps "deployment/$dep" --timeout=180s >/dev/null || fail "deployment/$dep did not become ready"
        ok "deployment/$dep ready"
    done
    kubectl rollout status -n apollo-airlines-ui deployment/frontend --timeout=180s >/dev/null || fail "deployment/frontend did not become ready"
    ok "deployment/frontend ready"

    step "8/8 Waiting for Envoy data-plane"
    kubectl wait --for=condition=Ready pod -n envoy-gateway-system \
        -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
        --timeout=100s >/dev/null || fail "Envoy data-plane pod did not become ready"
    ok "Envoy Gateway ready"

    wait_stage7
    wait_observability

    ok "Apollo Airlines Stage 7 installed via kustomize ($ENV)"
    echo "  Run 'bash scripts/verify.sh --mode kustomize' to run the verify suite"
    echo "  Run 'bash scripts/scaling-lab.sh' for the practical HPA + scheduling lab"
    echo "  Run 'bash scripts/teardown.sh --mode kustomize' to remove"
else
    fail "unknown mode: $MODE (expected helm or kustomize)"
fi
