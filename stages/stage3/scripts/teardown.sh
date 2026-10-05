#!/usr/bin/env bash

set -euo pipefail

CONTEXT="${1:-${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}}"

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 3 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

echo "=== Tearing down Stage 3 resources ==="

# Delete Gateway API resources first
kube delete gateway apollo-gateway -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true
kube delete referencegrant apollo-gateway-grant -n apollo-airlines-ui --ignore-not-found >/dev/null 2>&1 || true
kube delete gatewayclass eg --ignore-not-found --wait=false >/dev/null 2>&1 || true

# Delete core namespaces (this also terminates StatefulSets and drops PVCs)
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    echo "Deleting namespace $ns..."
    kube delete namespace "$ns" --ignore-not-found --wait=true
  fi
done

# Verify zero namespace residue
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    printf 'Stage 3 teardown failed: namespace %s still exists.\n' "$ns" >&2
    exit 1
  fi
done

printf 'Stage 3 teardown complete; cluster %s was retained.\n' "${CONTEXT#kind-}"
