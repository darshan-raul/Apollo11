#!/bin/bash
# Apply Stage 5: Apollo Airlines packaged as a Helm chart (default) or
# Kustomize overlays (--mode kustomize).
#
# Modes:
#   helm      — single `helm install` provisions the full cluster:
#                 * 2 namespaces (apps, ui)
#                 * 13 ServiceAccounts
#                 * 3 Postgres StatefulSets + headless SVCs + init ConfigMaps
#                 * 1 Redis StatefulSet + headless SVC
#                 * 6 app Deployments + 1 frontend Deployment
#                 * 2 PodDisruptionBudgets (booking, frontend)
#                 * 3 idempotent seed Jobs
#                 * Envoy Gateway install + GatewayClass + Gateway
#                 * 6 HTTPRoutes + 1 ReferenceGrant (cross-namespace)
#                 * MetalLB install + IPAddressPool + L2Advertisement
#
#   kustomize — applies overlays/{env}/ on top of the plain manifest base.
#               Useful for dev iteration. Does NOT install the access stack
#               (StatefulSets, Envoy, MetalLB, seed jobs); the chart owns
#               those.
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
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"

MODE="helm"
ENV="dev"
TAG="latest"
SKIP_BUILD=false
RELEASE_NAME="apollo11"

usage() {
    cat <<EOF
Usage: $0 [--mode MODE] [--env ENV] [--tag TAG] [--skip-build] [--release NAME]

Options:
  --mode MODE       helm (default) | kustomize
  --env ENV         dev (default) | staging | prod
                    helm mode:      picks helm/apollo11/values-\$ENV.yaml
                    kustomize mode: picks overlays/\$ENV/
  --tag TAG         Image tag (default: latest). Overrides the value in
                    the env-specific values file.
  --skip-build      Reuse pre-built images; skip the docker build step
  --release NAME    Helm release name (default: apollo11)
  --help            Show this help

Examples:
  $0                                          # helm install (defaults: tag=latest, no env file)
  $0 --env dev                                # helm with values-dev.yaml (1 replica, tag=dev)
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
        --tag)         TAG="$2"; shift 2 ;;
        --skip-build)  SKIP_BUILD=true; shift ;;
        --release)     RELEASE_NAME="$2"; shift 2 ;;
        --help)        usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validate env early so a typo doesn't surface mid-install
case "$ENV" in
    dev|staging|prod) ;;
    *) echo "Invalid --env '$ENV' (expected dev, staging, or prod)"; usage ;;
esac

# Colors
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/8 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
ok "cluster reachable"

# ---------------------------------------------------------------------------
# Phase 1: build + load images
# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" != "true" ]]; then
    step "1/8 Building + loading images (tag: $TAG)"
    bash "$SCRIPT_DIR/build-images.sh" --tag "$TAG" --cluster "$CLUSTER" || \
        echo "  (image build/load warnings — continuing)"
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
    step "2/8 Pre-install: CRD bundle (Envoy Gateway + MetalLB)"
    # Both bundles use --server-side for the >256KB last-applied-config
    # workaround. MetalLB needs --force-conflicts because its webhook
    # manages its own CA.
    if [[ -f "$CHART_DIR/bundles/envoy-gateway-install.yaml" ]]; then
        # Create the namespace first; the bundled install doesn't always
        # create it on its own.
        kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
        kubectl apply --server-side -f "$CHART_DIR/bundles/envoy-gateway-install.yaml" 2>&1 | tail -2
        ok "Envoy Gateway CRDs applied"
    fi
    if [[ -f "$CHART_DIR/bundles/metallb-native.yaml" ]]; then
        kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
        kubectl apply --server-side --force-conflicts -f "$CHART_DIR/bundles/metallb-native.yaml" 2>&1 | tail -2
        ok "MetalLB CRDs applied"
    fi

    step "3/8 Wait for CRD registration"
    # Wait until the API server can see the new CRDs
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && \
           kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
            ok "CRDs registered"
            break
        fi
        sleep 3
    done

    step "4/8 Wait for MetalLB webhook to be ready"
    # The MetalLB IPAddressPool has a validating webhook. The webhook
    # service must be up before the chart can create pool resources.
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        # Webhook endpoints become non-empty when the controller pod is up
        endpoints=$(kubectl get endpoints metallb-webhook-service -n metallb-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$endpoints" ]]; then
            ok "MetalLB webhook endpoint ready ($endpoints)"
            break
        fi
        sleep 3
    done

    step "5/8 Helm install (release: $RELEASE_NAME, env: $ENV)"
    HELM_CMD=(helm upgrade --install "$RELEASE_NAME" "$CHART_DIR"
        --namespace apollo-airlines-apps
        --create-namespace
        --set image.tag="$TAG"
        --set gateway.envoy.bundleInstall=false
        --set metallb.bundleInstall=false
        --wait --timeout 10m)

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

    # The chart creates envoy-gateway-system + metallb-system namespaces
    # via its bundled install YAMLs; verify they're up.
    step "6/8 Waiting for MetalLB controller pod"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if kubectl get pods -n metallb-system -l component=controller --no-headers 2>/dev/null | grep -q "1/1"; then
            ok "MetalLB controller ready"
            break
        fi
        sleep 5
    done

    step "7/8 Waiting for Envoy Gateway"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | grep -q "1/1"; then
            ok "Envoy Gateway ready"
            break
        fi
        sleep 5
    done

    step "8/8 Waiting for StatefulSets (3 PG + 1 Redis)"
    for sts in identity-db flight-db booking-db redis; do
        kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
            -n apollo-airlines-apps "statefulset/$sts" --timeout=120s 2>/dev/null && \
            ok "statefulset/$sts ready" || \
            echo "  (warn) statefulset/$sts not ready yet"
    done

    step "8/8 Waiting for seed jobs"
    # (no further steps)
    step "Final: waiting for app Deployments"
    for job in seed-identity-db seed-flight-db seed-booking-db; do
        kubectl wait --for=condition=Complete -n apollo-airlines-apps "job/$job" --timeout=120s 2>/dev/null && \
            ok "job/$job Complete" || \
            echo "  (warn) job/$job not complete"
    done

    step "7/8 Waiting for app Deployments (6 apps + frontend)"
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

    step "8/8 Summary"
    ok "Apollo Airlines installed via Helm"
    echo "  Run 'bash scripts/verify.sh --mode helm' to run the verify suite"
    echo "  Run 'bash scripts/teardown.sh --mode helm' to uninstall"

elif [[ "$MODE" == "kustomize" ]]; then
    # ---------------------------------------------------------------------
    # Kustomize: plain manifest base + dev/staging/prod overlay
    # ---------------------------------------------------------------------
    OVERLAY_DIR="$STAGE_DIR/overlays/$ENV"
    if [[ ! -d "$OVERLAY_DIR" ]]; then
        fail "overlay dir not found: $OVERLAY_DIR (env: $ENV)"
    fi

    step "2/8 Ensuring namespaces exist"
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

    step "3/8 ServiceAccounts (13 total)"
    # The kustomize base doesn't include SAs (intentionally — the
    # base is apps-only). Apply the chart's SA template directly.
    helm template "$RELEASE_NAME" "$CHART_DIR" --show-only templates/config/serviceaccount.yaml --namespace apollo-airlines-apps 2>/dev/null | \
        kubectl apply -f - 2>&1 | tail -3
    ok "ServiceAccounts applied"

    step "4/8 ConfigMap + Secret"
    helm template "$RELEASE_NAME" "$CHART_DIR" --show-only templates/config/configmap.yaml 2>/dev/null | kubectl apply -f -
    helm template "$RELEASE_NAME" "$CHART_DIR" --show-only templates/config/secrets.yaml 2>/dev/null | kubectl apply -f -
    ok "ConfigMap + Secret applied"

    step "5/8 Kustomize build ($ENV overlay)"
    # The base expects StatefulSets + DB hostnames to exist. For pure
    # kustomize, we ship a separate plain manifest for postgres/redis.
    # For now: apply the chart's infra templates + the kustomize overlay.
    echo "  Building kustomize overlay at $OVERLAY_DIR..."
    if ! kubectl kustomize "$OVERLAY_DIR" > /tmp/stage5-kustomize.yaml 2>/tmp/kustomize-err; then
        cat /tmp/kustomize-err
        fail "kustomize build failed"
    fi
    ok "kustomize build OK ($(wc -l < /tmp/stage5-kustomize.yaml) lines)"

    step "6/8 Applying kustomize overlay"
    kubectl apply -k "$OVERLAY_DIR"
    ok "kustomize overlay applied"

    step "7/8 Applying StatefulSets + jobs from chart (needed for the apps to work)"
    for tmpl in infra/postgres.yaml infra/redis.yaml jobs/seed.yaml; do
        helm template "$RELEASE_NAME" "$CHART_DIR" --show-only "templates/$tmpl" 2>/dev/null | kubectl apply -f - 2>&1 | tail -2
    done
    ok "StatefulSets + jobs applied"

    step "8/8 Waiting for StatefulSets"
    for sts in identity-db flight-db booking-db redis; do
        kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
            -n apollo-airlines-apps "statefulset/$sts" --timeout=120s 2>/dev/null && \
            ok "statefulset/$sts ready" || \
            echo "  (warn) statefulset/$sts not ready yet"
    done

    ok "Apollo Airlines installed via kustomize ($ENV)"
    echo "  Run 'bash scripts/verify.sh --mode kustomize' to run the verify suite"
    echo "  Run 'bash scripts/teardown.sh --mode kustomize' to remove"
else
    fail "unknown mode: $MODE (expected helm or kustomize)"
fi
