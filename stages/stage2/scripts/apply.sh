#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
SKIP_BUILD=false
SUBSTAGE=5

usage() {
  printf 'Usage: %s [--substage 1-5] [--skip-build] [--context kind-apollo11|kind-apollo11-dev]\n' "$0"
  printf '  --substage N   Deploy up to substage N (1: ClusterIP/DNS, 2: NodePort, 3: Traefik Ingress+TLS, 4: MetalLB, 5: Envoy Gateway [default])\n'
  printf '  --skip-build   Skip building and loading images into kind\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --substage) SUBSTAGE="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 2 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

kube cluster-info >/dev/null

if [[ "${SKIP_BUILD}" == false ]]; then
  cluster_name="${CONTEXT#kind-}"
  scheme=http
  [[ "$SUBSTAGE" == 5 ]] && scheme=https
  "${SCRIPT_DIR}/build-images.sh" --cluster "${cluster_name}" --scheme "$scheme"
fi

printf '\n[1/5] Applying namespaces, configuration, secrets, and ServiceAccounts\n'
kube apply -f "${STAGE_DIR}/k8s/config/00-namespaces.yaml"
kube apply -f "${STAGE_DIR}/k8s/config/configmap.yaml"
kube apply -f "${STAGE_DIR}/k8s/config/secrets.yaml"
kube apply -f "${STAGE_DIR}/k8s/config/serviceaccounts.yaml"

printf '\n[2/5] Applying database and Redis infrastructure\n'
for component in identity-db flight-db booking-db redis; do
  kube apply -f "${STAGE_DIR}/k8s/infra/${component}/${component}-dep.yaml"
  kube apply -f "${STAGE_DIR}/k8s/infra/${component}/${component}-svc.yaml"
done

printf 'Waiting for infrastructure rollouts...\n'
for component in identity-db flight-db booking-db redis; do
  kube rollout status "deployment/${component}" -n apollo-airlines-apps --timeout=180s
done

printf '\n[3/5] Applying database initialization Jobs\n'
kube apply -f "${STAGE_DIR}/k8s/jobs/identity-init-configmap.yaml"
kube apply -f "${STAGE_DIR}/k8s/jobs/flight-init-configmap.yaml"
kube apply -f "${STAGE_DIR}/k8s/jobs/booking-init-configmap.yaml"
kube delete jobs -n apollo-airlines-apps \
  init-identity-db init-flight-db init-booking-db \
  --ignore-not-found --wait=true
kube apply -f "${STAGE_DIR}/k8s/jobs/init-identity-db.yaml"
kube apply -f "${STAGE_DIR}/k8s/jobs/init-flight-db.yaml"
kube apply -f "${STAGE_DIR}/k8s/jobs/init-booking-db.yaml"

for job in init-identity-db init-flight-db init-booking-db; do
  kube wait --for=condition=Complete "job/${job}" -n apollo-airlines-apps --timeout=180s
done

printf '\n[4/5] Applying core application services\n'
for component in identity flight booking search notification; do
  kube apply -f "${STAGE_DIR}/k8s/apps/${component}/${component}-dep.yaml"
  kube apply -f "${STAGE_DIR}/k8s/apps/${component}/${component}-svc.yaml"
done
kube apply -f "${STAGE_DIR}/k8s/apps/frontend/frontend-dep.yaml"
kube apply -f "${STAGE_DIR}/k8s/apps/frontend/frontend-svc.yaml"

for component in identity flight booking search notification; do
  kube rollout status "deployment/${component}" -n apollo-airlines-apps --timeout=180s
done
kube rollout status deployment/frontend -n apollo-airlines-ui --timeout=180s

printf '\n[5/5] Configuring networking substage %s\n' "${SUBSTAGE}"

case "${SUBSTAGE}" in
  1)
    printf 'Applying Substage 1: Internal DNS and discovery\n'
    kube apply -f "${STAGE_DIR}/k8s/substages/01-internal-dns/curl-client.yaml"
    kube wait --for=condition=Ready pod/curl-client -n apollo-airlines-ui --timeout=60s
    ;;
  2)
    printf 'Applying Substage 2: NodePort direct access\n'
    kube apply -f "${STAGE_DIR}/k8s/substages/02-nodeport/nodeport-services.yaml"
    ;;
  3)
    printf 'Applying Substage 3: Traefik Ingress + Local TLS\n'
    "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/generate-certs.sh" --context "$CONTEXT"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/00-traefik-rbac-and-class.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/01-traefik-daemonset.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/01b-traefik-service.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/02-ingress-frontend.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/03-ingress-apps.yaml"
    kube rollout status daemonset/traefik -n kube-system --timeout=120s
    ;;
  4)
    printf 'Applying Substage 4: MetalLB + Traefik LoadBalancer\n'
    "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/generate-certs.sh" --context "$CONTEXT"
    kube apply -f "${STAGE_DIR}/k8s/substages/04-metallb/00-metallb-native.yaml"
    kube wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb,component=controller --timeout=120s
    kube apply -f "${STAGE_DIR}/k8s/substages/04-metallb/01-ip-pool.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/00-traefik-rbac-and-class.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/01-traefik-daemonset.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/04-metallb/traefik-loadbalancer-svc.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/02-ingress-frontend.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/03-ingress-apps.yaml"
    kube rollout status daemonset/traefik -n kube-system --timeout=120s
    ;;
  5)
    printf 'Applying Substage 5: MetalLB + Envoy Gateway API\n'
    # Ensure any Traefik resources are cleaned up
    kube delete ingress --all -n apollo-airlines-apps --ignore-not-found
    kube delete ingress --all -n apollo-airlines-ui --ignore-not-found
    kube delete service traefik -n kube-system --ignore-not-found
    kube delete daemonset traefik -n kube-system --ignore-not-found

    kube apply -f "${STAGE_DIR}/k8s/substages/04-metallb/00-metallb-native.yaml"
    kube wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb,component=controller --timeout=120s
    kube apply -f "${STAGE_DIR}/k8s/substages/04-metallb/01-ip-pool.yaml"

    kube apply --server-side -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/00-envoy-gateway-install.yaml"
    kube wait --namespace envoy-gateway-system --for=condition=ready pod --selector=control-plane=envoy-gateway --timeout=120s

    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/00a-gatewayclass.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/00b-envoyproxy.yaml"
    if ! kube get secret apollo-tls-secret -n apollo-airlines-apps &>/dev/null; then
      printf 'Generating TLS certificate for Envoy Gateway HTTPS listener...\n'
      bash "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/generate-certs.sh" --context "$CONTEXT"
    fi
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/01-gateway.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/02-httproute-identity.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/03-httproute-flight.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/04-httproute-booking.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/05-httproute-search.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/06-httproute-notification.yaml"
    kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/07-httproute-frontend.yaml"

    printf 'Waiting for Envoy Proxy and Gateway programming...\n'
    for i in {1..30}; do
      if kube get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -q '^[0-9]'; then
        break
      fi
      sleep 2
    done
    kube wait --for=condition=Programmed gateway/apollo-gateway -n apollo-airlines-apps --timeout=60s
    ;;
  *)
    printf 'Invalid substage: %s. Must be between 1 and 5.\n' "${SUBSTAGE}" >&2
    exit 2
    ;;
esac

printf '\nStage 2 (Substage %s) applied successfully.\n' "${SUBSTAGE}"
