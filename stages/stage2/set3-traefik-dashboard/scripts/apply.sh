#!/bin/bash
# Apply Set 3: Traefik Ingress (host-based, NodePort 30443) + dashboard.
# Same edge access as Set 2; adds the Traefik dashboard at traefik.apollo.local.
# Run from the set3-traefik-dashboard directory: ./scripts/apply.sh
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

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }

step "0/8 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
  exit 1
fi

step "1/8 Building + loading frontend image with apollo.local:30443 URLs"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  docker build -t "${REGISTRY}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="$VITE_IDENTITY_URL" \
    --build-arg VITE_FLIGHT_URL="$VITE_FLIGHT_URL" \
    --build-arg VITE_BOOKING_URL="$VITE_BOOKING_URL" \
    --build-arg VITE_SEARCH_URL="$VITE_SEARCH_URL" \
    "${SET_DIR}/../code/frontend/"
  for svc in $SERVICES; do
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER" 2>/dev/null && \
      ok "loaded ${REGISTRY}/${svc}:latest" || \
      echo "  (skip) ${REGISTRY}/${svc}:latest"
  done
else
  echo "  Cluster '$CLUSTER' is not a kind cluster, skipping image build/load"
fi

step "2/8 Namespaces + config + secrets"
kubectl apply -f "$K8S_DIR/config/"

step "3/8 ServiceAccounts"
kubectl apply -f "$K8S_DIR/serviceaccounts/"

# NetworkPolicies are NOT applied automatically (kindnet doesn't enforce).
# See set1-baseline/README.md for details.

step "4/8 Apps + infra (10 components, ClusterIP)"
kubectl apply -f "$K8S_DIR/apps/" --recursive

step "5/8 Init jobs (3 DBs)"
kubectl apply -f "$K8S_DIR/jobs/"

step "6/8 Traefik CRDs (needed for IngressRoute)"
kubectl apply --server-side -f https://raw.githubusercontent.com/traefik/traefik/v3.1/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml >/dev/null 2>&1 || true

step "7/8 Traefik (ConfigMap + DaemonSet + RBAC + IngressClass + 5 Ingresses + dashboard IngressRoute)"
kubectl apply -f "$K8S_DIR/ingress/" --recursive

step "8/8 /etc/hosts reminder"
cat <<EOF

${GREEN}Add these lines to your /etc/hosts:${NC}
  127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \\
              booking.apollo.local search.apollo.local \\
              traefik.apollo.local

Then test with:
  curl -H 'Host: identity.apollo.local' http://localhost:30443/api/users/login \\
    -H 'Content-Type: application/json' \\
    -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
  open http://frontend.apollo.local:30443
  open http://traefik.apollo.local:30443    # Traefik dashboard (no auth)
EOF

ok "Set 3 applied. Wait ~30s then run ./scripts/verify.sh"
