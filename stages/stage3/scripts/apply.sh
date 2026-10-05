#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${STAGE_DIR}/k8s"
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
SKIP_BUILD=false

usage() {
  printf 'Usage: %s [--skip-build] [--context kind-apollo11|kind-apollo11-dev]\n' "$0"
  printf '  --skip-build   Skip building and loading images into kind\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 3 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

kube cluster-info >/dev/null

if [[ "${SKIP_BUILD}" == false ]]; then
  cluster_name="${CONTEXT#kind-}"
  "${SCRIPT_DIR}/build-images.sh" --cluster "${cluster_name}"
fi

printf '\n[1/7] Applying namespaces, configuration, secrets, and ServiceAccounts\n'
kube apply -f "${K8S_DIR}/config/"

printf '\n[2/7] Applying stateful workloads (StatefulSets + Headless Services + Schema ConfigMaps)\n'
kube apply -f "${K8S_DIR}/apps/" --recursive

printf 'Waiting for StatefulSets to report ready replicas (schema bootstrap runs via entrypoint hook)...\n'
for sts in identity-db flight-db booking-db redis; do
  kube rollout status "statefulset/${sts}" -n apollo-airlines-apps --timeout=180s
done

for db in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  kube wait --for=condition=Ready "pod/${db}" -n apollo-airlines-apps --timeout=60s
done

printf '\n[3/7] Waiting for application Deployments...\n'
for dep in identity flight booking search notification; do
  kube rollout status "deployment/${dep}" -n apollo-airlines-apps --timeout=180s
done
kube rollout status deployment/frontend -n apollo-airlines-ui --timeout=180s

printf '\n[4/7] Applying idempotent database seed Jobs\n'
kube delete jobs -n apollo-airlines-apps \
  seed-identity-db seed-flight-db seed-booking-db \
  --ignore-not-found --wait=true
kube apply -f "${K8S_DIR}/jobs/"

for job in seed-identity-db seed-flight-db seed-booking-db; do
  kube wait --for=condition=Complete "job/${job}" -n apollo-airlines-apps --timeout=180s
done

printf '\n[5/7] Applying MetalLB LoadBalancer infrastructure\n'
kube apply -f "${K8S_DIR}/metallb/00-metallb-native.yaml"
kube wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb,component=controller --timeout=120s
kube apply -f "${K8S_DIR}/metallb/01-ip-pool.yaml"

printf '\n[6/7] Applying Envoy Gateway API controller and CRDs\n'
kube apply --server-side -f "${K8S_DIR}/gateway/00-envoy-gateway-install.yaml"
kube wait --namespace envoy-gateway-system --for=condition=ready pod --selector=control-plane=envoy-gateway --timeout=120s

printf '\n[7/7] Applying GatewayClass, EnvoyProxy, Gateway, ReferenceGrant, and HTTPRoutes\n'
kube apply -f "${K8S_DIR}/gateway/00a-gatewayclass.yaml"
kube apply -f "${K8S_DIR}/gateway/00b-envoyproxy.yaml"
if ! kube get secret apollo-tls-secret -n apollo-airlines-apps &>/dev/null; then
  printf 'Generating TLS certificate for Envoy Gateway HTTPS listener...\n'
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

printf 'Waiting for Envoy Proxy and Gateway programming...\n'
for i in {1..30}; do
  if kube get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -q '^[0-9]'; then
    break
  fi
  sleep 2
done
kube wait --for=condition=Programmed gateway/apollo-gateway -n apollo-airlines-apps --timeout=60s

LB_IP=$(kube get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
printf '\nStage 3 applied successfully. Envoy Gateway IP: %s\n' "${LB_IP}"
