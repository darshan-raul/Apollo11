#!/bin/bash
# Teardown Set 3: removes both namespaces, Traefik, and the Traefik CRDs.
# Run from the set3-traefik-dashboard directory: ./scripts/teardown.sh
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

step "Deleting Traefik CRDs (cluster-scoped, installed by set 3 apply.sh)"
kubectl delete -f https://raw.githubusercontent.com/traefik/traefik/v3.1/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml --ignore-not-found 2>&1 | tail -3 || true

ok "Set 3 teardown complete"
