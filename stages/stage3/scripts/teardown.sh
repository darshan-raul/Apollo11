#!/bin/bash
# Teardown Stage 3: removes the two namespaces, Envoy Gateway, and MetalLB.
# Also explicitly deletes the PVCs so the underlying local-path volumes are
# released cleanly (kind's local-path provisioner reclaims them with the PV
# when the PVC is deleted).
# Run from stages/stage3: ./scripts/teardown.sh
#
# Order matters:
#   1. Delete app namespaces (everything in them, including PVCs)
#   2. Delete the Gateway + HTTPRoutes (releases the gatewayclass binding
#      to apollo-gateway so we can delete the GatewayClass cleanly)
#   3. Delete Envoy Gateway install (CRDs, controller, webhooks)
#   4. Delete MetalLB
# Doing it in the wrong order hangs on apiservices/webhooks that depend
# on deleted namespaces.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$STAGE_DIR/k8s"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }

step "Deleting apollo-airlines-* namespaces (this also drops all PVCs)"
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    kubectl delete ns "$ns" --wait=false
    ok "deleted namespace $ns (async)"
  else
    echo "  namespace $ns already gone"
  fi
done

step "Deleting the Gateway and HTTPRoutes"
kubectl delete gateway apollo-gateway -n apollo-airlines-apps --ignore-not-found 2>&1 | tail -1 || true
for rt in identity flight booking search notification frontend; do
  kubectl delete httproute "$rt" -n apollo-airlines-apps --ignore-not-found 2>&1 | tail -1 || true
done
ok "Gateway + HTTPRoutes deleted"

step "Deleting Envoy Gateway (CRDs + controller + webhooks)"
if [[ -f "$K8S_DIR/gateway/00-envoy-gateway-install.yaml" ]]; then
  # Use timeout to avoid hanging on apiservice deletions.
  timeout 60 kubectl delete -f "$K8S_DIR/gateway/00-envoy-gateway-install.yaml" --ignore-not-found 2>&1 | tail -3
  # Force-delete the namespace if it's still Terminating.
  if kubectl get ns envoy-gateway-system >/dev/null 2>&1; then
    timeout 30 kubectl delete ns envoy-gateway-system --force --grace-period=0 2>&1 | tail -2 || true
  fi
  ok "Envoy Gateway uninstalled"
fi

step "Deleting MetalLB"
if [[ -f "$K8S_DIR/metallb/00-metallb-native.yaml" ]]; then
  timeout 60 kubectl delete -f "$K8S_DIR/metallb/00-metallb-native.yaml" --ignore-not-found 2>&1 | tail -3
  if kubectl get ns metallb-system >/dev/null 2>&1; then
    timeout 30 kubectl delete ns metallb-system --force --grace-period=0 2>&1 | tail -2 || true
  fi
  ok "MetalLB uninstalled"
fi

step "Waiting for namespace finalizers to clear"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  active=$(kubectl get ns 2>&1 | grep -cE "apollo-airlines|envoy-gateway-system|metallb-system" || echo 0)
  if [[ "$active" == "0" ]]; then
    ok "all target namespaces are gone"
    break
  fi
  sleep 2
done

ok "Stage 3 teardown complete"
