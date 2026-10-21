#!/usr/bin/env bash

set -euo pipefail

CONTEXT="${1:-${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}}"

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 4 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

echo "=== Tearing down Stage 4 resources ==="

# Delete Gateway API resources first
kube delete gateway apollo-gateway -n apollo-airlines-apps --ignore-not-found --wait=false >/dev/null 2>&1 || true
kube delete referencegrant apollo-gateway-grant -n apollo-airlines-ui --ignore-not-found >/dev/null 2>&1 || true
kube delete gatewayclass eg --ignore-not-found --wait=false >/dev/null 2>&1 || true

# Delete cluster-scoped PriorityClasses
kube delete priorityclass apollo-airlines-app-critical apollo-airlines-app-low --ignore-not-found >/dev/null 2>&1 || true

# Delete core namespaces (this also terminates StatefulSets, Deployments, PDBs and drops PVCs)
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    echo "Deleting namespace $ns..."
    kube delete namespace "$ns" --ignore-not-found --wait=true
  fi
done

# Cluster-scoped objects installed by MetalLB and Envoy Gateway outlive their
# namespaces. Remove them only when nothing outside this stage still uses the
# shared CRDs, so another workload on the cluster never loses its resources.
PLATFORM_CRD_PATTERN='envoyproxy\.io|gateway\.networking\.(x-)?k8s\.io|metallb\.io'
OWNED_NS='^(apollo-airlines-apps|apollo-airlines-ui|envoy-gateway-system|metallb-system)$'
foreign=()
for crd in $(kube get crd -o name 2>/dev/null | grep -E "$PLATFORM_CRD_PATTERN" | sed 's|.*/||' || true); do
  # Each line is namespace/name; cluster-scoped objects have an empty namespace.
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    ns="${ref%%/*}"
    name="${ref#*/}"
    if [[ -z "$ns" ]]; then
      [[ "$crd" == gatewayclasses.gateway.networking.k8s.io && "$name" == eg ]] && continue
      foreign+=("$crd $name")
    elif [[ ! "$ns" =~ $OWNED_NS ]]; then
      foreign+=("$crd $ns/$name")
    fi
  done < <(kube get "$crd" -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
done
if [[ ${#foreign[@]} -gt 0 ]]; then
  printf 'Kept the Gateway API, Envoy Gateway and MetalLB CRDs: these objects outside this stage still use them:\n' >&2
  printf '  %s\n' "${foreign[@]}" >&2
  exit 1
fi
kube delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found >/dev/null 2>&1 || true
kube delete mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system --ignore-not-found >/dev/null 2>&1 || true
kube delete clusterrolebinding metallb-system:controller metallb-system:speaker \
  eg-gateway-helm-envoy-gateway-rolebinding eg-gateway-helm-certgen:envoy-gateway-system \
  --ignore-not-found >/dev/null 2>&1 || true
kube delete clusterrole metallb-system:controller metallb-system:speaker \
  eg-gateway-helm-envoy-gateway-role eg-gateway-helm-certgen:envoy-gateway-system \
  --ignore-not-found >/dev/null 2>&1 || true
for crd in $(kube get crd -o name 2>/dev/null | grep -E "$PLATFORM_CRD_PATTERN" || true); do
  kube delete "$crd" --ignore-not-found >/dev/null 2>&1 || true
done

# Verify zero namespace residue
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    printf 'Stage 4 teardown failed: namespace %s still exists.\n' "$ns" >&2
    exit 1
  fi
done

if kube get crd -o name 2>/dev/null | grep -qE 'envoyproxy\.io|gateway\.networking\.(x-)?k8s\.io|metallb\.io'; then
  printf 'Stage 4 teardown failed: Gateway API, Envoy Gateway or MetalLB CRDs still exist.\n' >&2
  exit 1
fi

printf 'Stage 4 teardown complete; cluster %s was retained.\n' "${CONTEXT#kind-}"
