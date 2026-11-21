#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="${STAGE_DIR}/k8s"
CLUSTER=""
CONTEXT="${KUBE_CONTEXT:-}"

SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [--skip-build] [--cluster NAME] [--context kind-apollo11|kind-apollo11-dev]"
            exit 0
            ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --cluster) [[ $# -ge 2 ]] || { echo "--cluster requires a value" >&2; exit 2; }; CLUSTER="$2"; shift 2 ;;
        --context) [[ $# -ge 2 ]] || { echo "--context requires a value" >&2; exit 2; }; CONTEXT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

CONTEXT="${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
CLUSTER="${CLUSTER:-apollo11}"
ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev")

echo "=== Applying Stage 4: Flight Control (Probes, QoS, Scheduling, Disruption) ==="

ctx_matched=false
for allowed in "${ALLOWED_CONTEXTS[@]}"; do
    if [[ "$CONTEXT" == "$allowed" ]]; then
        ctx_matched=true
        break
    fi
done

if [[ "$ctx_matched" != "true" ]]; then
    echo "Refusing to run against context '${CONTEXT:-<none>}'." >&2
    echo "This script only targets one of: ${ALLOWED_CONTEXTS[*]}" >&2
    exit 2
fi

kube() {
    kubectl --context "$CONTEXT" "$@"
}

if [[ "$SKIP_BUILD" != "true" ]]; then
    echo ""
    echo "[1/8] Building and loading service images..."
    bash "${SCRIPT_DIR}/build-images.sh" --cluster "${CONTEXT#kind-}"
else
    echo ""
    echo "[1/8] Skipping image build (--skip-build)"
fi

echo ""
echo "[2/8] Applying config, secrets, ServiceAccounts, and PriorityClasses..."
kube apply -f "${K8S_DIR}/config/"

echo ""
echo "[3/8] Applying stateful databases & Redis..."
for stateful in identity-db flight-db booking-db redis; do
    kube apply -f "${K8S_DIR}/apps/${stateful}/"
done

echo ""
echo "[4/8] Waiting for StatefulSets and pods to be Ready..."
for sts in identity-db flight-db booking-db redis; do
    kube rollout status "statefulset/${sts}" -n apollo-airlines-apps --timeout=120s
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    kube wait --for=condition=Ready "pod/${pod}" -n apollo-airlines-apps --timeout=60s
done

echo ""
echo "[5/8] Running idempotent database seed Jobs..."
kube delete job seed-identity-db seed-flight-db seed-booking-db -n apollo-airlines-apps --ignore-not-found >/dev/null 2>&1 || true
kube apply -f "${K8S_DIR}/jobs/"
for job in seed-identity-db seed-flight-db seed-booking-db; do
    kube wait --for=condition=Complete "job/${job}" -n apollo-airlines-apps --timeout=90s
done

echo ""
echo "[6/8] Applying stateless application Deployments & PDBs and waiting for rollout..."
for app_dir in identity flight booking search notification frontend; do
    kube apply -f "${K8S_DIR}/apps/${app_dir}/"
done
kube apply -f "${K8S_DIR}/pdb/"
for dep in identity flight booking search notification; do
    kube rollout status "deployment/${dep}" -n apollo-airlines-apps --timeout=120s
done
kube rollout status deployment/frontend -n apollo-airlines-ui --timeout=120s

echo ""
echo "[7/8] Applying MetalLB LoadBalancer infrastructure..."
kube apply --server-side --force-conflicts -f "${K8S_DIR}/metallb/00-metallb-native.yaml"
kube wait --for=condition=Ready pod -l component=controller -n metallb-system --timeout=120s
kube apply -f "${K8S_DIR}/metallb/01-ip-pool.yaml"

echo ""
echo "[8/8] Applying Envoy Gateway API controller, GatewayClass, EnvoyProxy, and HTTPRoutes..."
kube apply --server-side --force-conflicts -f "${K8S_DIR}/gateway/00-envoy-gateway-install.yaml"
kube wait --for=condition=Ready pod -l control-plane=envoy-gateway -n envoy-gateway-system --timeout=120s
kube apply -f "${K8S_DIR}/gateway/00a-gatewayclass.yaml"
kube apply -f "${K8S_DIR}/gateway/00b-envoyproxy.yaml"
if ! kube get secret apollo-tls-secret -n apollo-airlines-apps &>/dev/null; then
    echo "Generating TLS certificate for Envoy Gateway HTTPS listener..."
    bash "${SCRIPT_DIR}/generate-certs.sh" --context "$CONTEXT"
fi
kube apply -f "${K8S_DIR}/gateway/01-gateway.yaml"
kube apply -f "${K8S_DIR}/gateway/01a-referencegrant.yaml"
kube apply -f "${K8S_DIR}/gateway/02-httproute-identity.yaml"
kube apply -f "${K8S_DIR}/gateway/03-httproute-flight.yaml"
kube apply -f "${K8S_DIR}/gateway/04-httproute-booking.yaml"
kube apply -f "${K8S_DIR}/gateway/05-httproute-search.yaml"
kube apply -f "${K8S_DIR}/gateway/06-httproute-notification.yaml"
kube apply -f "${K8S_DIR}/gateway/07-httproute-frontend.yaml"

echo "Waiting for Envoy Proxy and Gateway programming..."
kube wait --for=condition=Programmed gateway/apollo-gateway -n apollo-airlines-apps --timeout=60s

GATEWAY_IP=""
for _ in $(seq 1 30); do
    GATEWAY_IP="$(kube get service -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "$GATEWAY_IP" ]]; then
        break
    fi
    sleep 2
done

echo ""
if [[ -n "$GATEWAY_IP" ]]; then
    echo "Stage 4 applied successfully. Envoy Gateway IP: ${GATEWAY_IP}"
else
    echo "Stage 4 apply failed: Envoy Gateway LoadBalancer IP is still pending." >&2
    exit 1
fi
