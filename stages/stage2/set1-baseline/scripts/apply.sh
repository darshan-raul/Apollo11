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
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/7 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi

step "1/7 Building frontend image + loading images into kind"
"${SCRIPT_DIR}/build-images.sh"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  for svc in $SERVICES; do
    if kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER"; then
      ok "loaded ${REGISTRY}/${svc}:latest"
    else
      fail "kind load failed for ${REGISTRY}/${svc}:latest — the cluster will run a stale image. Check that the cluster is running and your user has docker perms."
    fi
  done
  # Force a pod restart so the new image content is loaded. The frontend
  # Deployment has imagePullPolicy: Always, so this works even with the
  # Docker layer cache (which can return a stale image if the build-args
  # only changed content baked by Vite, not Dockerfile layers).
  kubectl rollout restart deployment/frontend -n apollo-airlines-ui >/dev/null
  kubectl rollout status deployment/frontend -n apollo-airlines-ui --timeout=120s >/dev/null
  ok "frontend rolled out with fresh image"
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
