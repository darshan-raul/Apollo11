#!/bin/bash
# Apply Set 2: Traefik Ingress (host-based, NodePort 30443).
# Run from the set2-ingress directory: ./scripts/apply.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SET_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$SET_DIR/k8s"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
SERVICES="identity flight booking search notification frontend"

# Traefik v3 URLs the frontend image needs baked in
VITE_IDENTITY_URL="http://identity.apollo.local:30443"
VITE_FLIGHT_URL="http://flight.apollo.local:30443"
VITE_BOOKING_URL="http://booking.apollo.local:30443"
VITE_SEARCH_URL="http://search.apollo.local:30443"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/7 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi

step "1/7 Building + loading frontend image with apollo.local:30443 URLs"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  # --no-cache forces a fresh build. Without it, the Docker layer cache
  # returns the previous image if the Dockerfile's COPY layers are
  # identical — but the VITE_* build-args can change the OUTPUT (Vite
  # bakes them into the JS bundle) without changing the input layers.
  # Result: a silently-stale image with old URLs. The cost is one full
  # build per run, which is negligible for a small frontend.
  docker build --no-cache -t "${REGISTRY}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="$VITE_IDENTITY_URL" \
    --build-arg VITE_FLIGHT_URL="$VITE_FLIGHT_URL" \
    --build-arg VITE_BOOKING_URL="$VITE_BOOKING_URL" \
    --build-arg VITE_SEARCH_URL="$VITE_SEARCH_URL" \
    "${SET_DIR}/../code/frontend/"
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
  echo "  Cluster '$CLUSTER' is not a kind cluster, skipping image build/load"
fi

step "2/7 Namespaces + config + secrets"
kubectl apply -f "$K8S_DIR/config/"

step "3/7 ServiceAccounts"
kubectl apply -f "$K8S_DIR/serviceaccounts/"

# NetworkPolicies are NOT applied automatically (kindnet doesn't enforce).
# See set1-baseline/README.md for details.

step "4/7 Apps + infra (10 components, ClusterIP)"
kubectl apply -f "$K8S_DIR/apps/" --recursive

step "5/7 Init jobs (3 DBs)"
kubectl apply -f "$K8S_DIR/jobs/"

step "6/7 Traefik (DaemonSet + RBAC + IngressClass + 5 Ingresses)"
kubectl apply -f "$K8S_DIR/ingress/" --recursive

step "7/7 /etc/hosts reminder"
cat <<EOF

${GREEN}Add these lines to your /etc/hosts:${NC}
  127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \\
              booking.apollo.local search.apollo.local

Then test with:
  curl -H 'Host: identity.apollo.local' http://localhost:30443/api/users/login \\
    -H 'Content-Type: application/json' \\
    -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
  open http://frontend.apollo.local:30443
EOF

ok "Set 2 applied. Wait ~30s then run ./scripts/verify.sh"
