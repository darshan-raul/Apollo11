#!/bin/bash
# Teardown Set 4: removes both namespaces, Traefik, and MetalLB.
# Run from the set4-metallb-traefik directory: ./scripts/teardown.sh
set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }

step "Deleting apollo-airlines-* namespaces"
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    kubectl delete ns "$ns" --wait=false
    ok "deleted namespace $ns"
  else
    echo "  (skip) namespace $ns does not exist"
  fi
done

step "Deleting Traefik from kube-system"
if kubectl get ns kube-system >/dev/null 2>&1; then
  for r in daemonset/traefik clusterrole/traefik clusterrolebinding/traefik \
           serviceaccount/traefik ingressclass.networking.k8s.io/traefik; do
    kubectl delete "$r" -n kube-system 2>/dev/null && ok "deleted $r" || true
  done
fi

step "Deleting MetalLB (cluster-scoped resources + namespace)"
if kubectl get ns metallb-system >/dev/null 2>&1; then
  kubectl delete ns metallb-system --wait=false
  ok "deleted namespace metallb-system"
fi

ok "Set 4 teardown complete"
