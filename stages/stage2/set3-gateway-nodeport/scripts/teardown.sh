#!/bin/bash
# Teardown Set 3: removes both namespaces and Envoy Gateway.
# Run from the set3-gateway-nodeport directory: ./scripts/teardown.sh
set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }

step "Deleting apollo-airlines-* namespaces"
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    kubectl delete ns "$ns" --wait=false
    ok "deleted namespace $ns"
  fi
done

step "Deleting Envoy Gateway (via install.yaml)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SET_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$SET_DIR/k8s/gateway/00-envoy-gateway-install.yaml" ]]; then
  kubectl delete -f "$SET_DIR/k8s/gateway/00-envoy-gateway-install.yaml" --ignore-not-found 2>&1 | tail -3
  ok "Envoy Gateway uninstalled"
fi

ok "Set 3 teardown complete"
