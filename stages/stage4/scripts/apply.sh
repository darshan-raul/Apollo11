#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="${STAGE_DIR}/k8s"
CLUSTER="${CLUSTER:-apollo11}"
ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev")

SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build) SKIP_BUILD=true; shift ;;
        --cluster) CLUSTER="$2"; ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev"); shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=== Applying Stage 4: Flight Control (Probes, QoS, Scheduling, Disruption) ==="

CURRENT_CTX="$(kubectl config current-context 2>/dev/null || true)"
ctx_matched=false
for allowed in "${ALLOWED_CONTEXTS[@]}"; do
    if [[ "$CURRENT_CTX" == "$allowed" ]]; then
        ctx_matched=true
        break
    fi
done

if [[ "$ctx_matched" != "true" ]]; then
    echo "Refusing to run against context '$CURRENT_CTX'."
    echo "This script only targets one of: ${ALLOWED_CONTEXTS[*]}"
    exit 1
fi

if [[ "$SKIP_BUILD" != "true" ]]; then
    echo ""
    echo "[1/8] Building and loading service images..."
    bash "${SCRIPT_DIR}/build-images.sh" --cluster "$CLUSTER"
else
    echo ""
    echo "[1/8] Skipping image build (--skip-build)"
fi

echo ""
echo "[2/8] Applying config, secrets, ServiceAccounts, and PriorityClasses..."
kubectl apply -f "${K8S_DIR}/config/"

echo ""
echo "[3/8] Applying stateful and stateless application workloads & PDBs..."
kubectl apply -f "${K8S_DIR}/apps/" --recursive
kubectl apply -f "${K8S_DIR}/pdb/"

echo ""
echo "[4/8] Waiting for StatefulSets and pods to be Ready..."
for sts in identity-db flight-db booking-db redis; do
    kubectl rollout status "statefulset/${sts}" -n apollo-airlines-apps --timeout=120s
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
    kubectl wait --for=condition=Ready "pod/${pod}" -n apollo-airlines-apps --timeout=60s
done

echo ""
echo "[5/8] Waiting for application Deployments to roll out..."
for dep in identity flight booking search notification; do
    kubectl rollout status "deployment/${dep}" -n apollo-airlines-apps --timeout=120s
done
kubectl rollout status deployment/frontend -n apollo-airlines-ui --timeout=120s

echo ""
echo "[6/8] Applying idempotent database seed Jobs..."
kubectl apply -f "${K8S_DIR}/jobs/"
for job in seed-identity-db seed-flight-db seed-booking-db; do
    kubectl wait --for=condition=Complete "job/${job}" -n apollo-airlines-apps --timeout=60s
done

echo ""
echo "[7/8] Applying MetalLB LoadBalancer infrastructure..."
kubectl apply --server-side --force-conflicts -f "${K8S_DIR}/metallb/00-metallb-native.yaml"
kubectl wait --for=condition=Ready pod -l component=controller -n metallb-system --timeout=120s
kubectl apply -f "${K8S_DIR}/metallb/01-ip-pool.yaml"

echo ""
echo "[8/8] Applying Envoy Gateway API controller, GatewayClass, EnvoyProxy, and HTTPRoutes..."
kubectl apply --server-side -f "${K8S_DIR}/gateway/00-envoy-gateway-install.yaml"
kubectl wait --for=condition=Ready pod -l control-plane=envoy-gateway -n envoy-gateway-system --timeout=120s
kubectl apply -f "${K8S_DIR}/gateway/00a-gatewayclass.yaml"
kubectl apply -f "${K8S_DIR}/gateway/00b-envoyproxy.yaml"
if ! kubectl get secret apollo-tls-secret -n apollo-airlines-apps &>/dev/null; then
    echo "Generating TLS certificate for Envoy Gateway HTTPS listener..."
    bash "${STAGE_DIR}/../stage2/k8s/substages/03-traefik-ingress-tls/generate-certs.sh"
fi
kubectl apply -f "${K8S_DIR}/gateway/01-gateway.yaml"
kubectl apply -f "${K8S_DIR}/gateway/01a-referencegrant.yaml"
kubectl apply -f "${K8S_DIR}/gateway/02-httproute-identity.yaml"
kubectl apply -f "${K8S_DIR}/gateway/03-httproute-flight.yaml"
kubectl apply -f "${K8S_DIR}/gateway/04-httproute-booking.yaml"
kubectl apply -f "${K8S_DIR}/gateway/05-httproute-search.yaml"
kubectl apply -f "${K8S_DIR}/gateway/06-httproute-notification.yaml"
kubectl apply -f "${K8S_DIR}/gateway/07-httproute-frontend.yaml"

echo "Waiting for Envoy Proxy and Gateway programming..."
kubectl wait --for=condition=Programmed gateway/apollo-gateway -n apollo-airlines-apps --timeout=60s

GATEWAY_IP=""
for _ in $(seq 1 30); do
    GATEWAY_IP="$(kubectl get service -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "$GATEWAY_IP" ]]; then
        break
    fi
    sleep 2
done

echo ""
if [[ -n "$GATEWAY_IP" ]]; then
    echo "Stage 4 applied successfully. Envoy Gateway IP: ${GATEWAY_IP}"
else
    echo "Stage 4 applied, but LoadBalancer IP is still pending."
fi
