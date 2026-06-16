#!/bin/bash
# Apply Set 1: Baseline (3 namespaces, NetworkPolicies, NodePort).
# Run from the set1-baseline directory: ./scripts/apply.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SET_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$SET_DIR/k8s"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
SERVICES="identity flight booking search notification frontend"

# Colors
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }

step "0/6 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
  exit 1
fi

step "1/6 Building frontend image + loading images into kind"
"${SCRIPT_DIR}/build-images.sh"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  for svc in $SERVICES; do
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER" 2>/dev/null && \
      ok "loaded ${REGISTRY}/${svc}:latest" || \
      echo "  (skip) ${REGISTRY}/${svc}:latest"
  done
else
  echo "  Cluster '$CLUSTER' is not a kind cluster, skipping image load"
fi

step "2/6 Namespaces + config + secrets"
kubectl apply -f "$K8S_DIR/config/"

step "3/6 ServiceAccounts"
kubectl apply -f "$K8S_DIR/serviceaccounts/"

# NetworkPolicies are NOT applied automatically. The default kindnet CNI does
# not enforce NetworkPolicy, so applying them is a no-op in this cluster.
# The manifests under k8s/networkpolicies/ are kept as reference material —
# apply them manually with `kubectl apply -f k8s/networkpolicies/` to study
# the policy model, but expect a CNI upgrade (Calico/Cilium) for real
# enforcement. See README for details.

step "4/6 Apps + infra (10 components, NodePort)"
kubectl apply -f "$K8S_DIR/apps/" --recursive

step "5/6 Init jobs (3 DBs)"
kubectl apply -f "$K8S_DIR/jobs/"

ok "Set 1 applied. Wait ~30s then run ./scripts/verify.sh"
