#!/bin/bash
# Apply Set 4: Envoy Gateway + MetalLB L2 (real LoadBalancer IP).
# Run from the set4-metallb-gateway directory: ./scripts/apply.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SET_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$SET_DIR/k8s"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
SERVICES="identity flight booking search notification frontend"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }

step "0/9 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
  exit 1
fi

step "1/9 Building + loading frontend image (URLs: <svc>.apollo.local — real IP from MetalLB)"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  docker build -t "${REGISTRY}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="http://identity.apollo.local" \
    --build-arg VITE_FLIGHT_URL="http://flight.apollo.local" \
    --build-arg VITE_BOOKING_URL="http://booking.apollo.local" \
    --build-arg VITE_SEARCH_URL="http://search.apollo.local" \
    "${SET_DIR}/../code/frontend/"
  for svc in $SERVICES; do
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER" 2>/dev/null && \
      ok "loaded ${REGISTRY}/${svc}:latest" || \
      echo "  (skip) ${REGISTRY}/${svc}:latest"
  done
else
  echo "  Cluster '$CLUSTER' is not a kind cluster, skipping image build/load"
fi

step "2/9 Namespaces + config + secrets"
kubectl apply -f "$K8S_DIR/config/"

step "3/9 ServiceAccounts"
kubectl apply -f "$K8S_DIR/serviceaccounts/"

# NetworkPolicies are NOT applied automatically (kindnet doesn't enforce).

step "4/9 Apps + infra (10 components, ClusterIP)"
kubectl apply -f "$K8S_DIR/apps/" --recursive

step "5/9 Init jobs (3 DBs)"
kubectl apply -f "$K8S_DIR/jobs/"

step "6/9 MetalLB install + IP pool + L2 advertisement"
# metallb-native.yaml is ~1900 lines; use --server-side for safety.
# --force-conflicts handles webhook cert rotation that MetalLB manages itself.
kubectl apply --server-side --force-conflicts -f "$K8S_DIR/metallb/00-metallb-native.yaml" 2>&1 | tail -3
# Wait for MetalLB webhook to be ready before creating IP pool
echo "  Waiting for MetalLB controller..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if kubectl get pods -n metallb-system -l component=controller --no-headers 2>/dev/null | grep -q "1/1"; then
    ok "MetalLB controller ready"
    break
  fi
  sleep 5
done
kubectl apply -f "$K8S_DIR/metallb/01-ip-pool.yaml"

step "7/9 Envoy Gateway install (CRDs + controller)"
kubectl apply --server-side -f "$K8S_DIR/gateway/00-envoy-gateway-install.yaml"
kubectl apply -f "$K8S_DIR/gateway/00a-gatewayclass.yaml"

step "8/9 Gateway + HTTPRoutes + cross-namespace ReferenceGrant"
kubectl apply -f "$K8S_DIR/gateway/01-gateway.yaml"
kubectl apply -f "$K8S_DIR/gateway/01a-referencegrant.yaml"
kubectl apply -f "$K8S_DIR/gateway/02-httproute-identity.yaml"
kubectl apply -f "$K8S_DIR/gateway/03-httproute-flight.yaml"
kubectl apply -f "$K8S_DIR/gateway/04-httproute-booking.yaml"
kubectl apply -f "$K8S_DIR/gateway/05-httproute-search.yaml"
kubectl apply -f "$K8S_DIR/gateway/06-httproute-notification.yaml"
kubectl apply -f "$K8S_DIR/gateway/07-httproute-frontend.yaml"

echo "  Waiting for Envoy Gateway to Program the Gateway..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  if [[ "$prog" == "True" ]]; then
    ok "Gateway is Programmed"
    break
  fi
  sleep 5
done

# Wait for MetalLB to assign a LoadBalancer IP
ENVOY_IP=""
echo "  Waiting for MetalLB to assign LoadBalancer IP..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
  SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$SVC" ]]; then
    ENVOY_IP=$(kubectl get svc "$SVC" -n envoy-gateway-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$ENVOY_IP" ]]; then
      ok "MetalLB assigned IP: $ENVOY_IP to $SVC"
      break
    fi
  fi
  sleep 5
done

step "9/9 /etc/hosts reminder"
if [[ -n "$ENVOY_IP" ]]; then
  cat <<EOF

${GREEN}Add these lines to your /etc/hosts:${NC}
  $ENVOY_IP  frontend.apollo.local identity.apollo.local flight.apollo.local \\
              booking.apollo.local search.apollo.local

Then test with:
  curl -H 'Host: identity.apollo.local' http://$ENVOY_IP/healthz
  open http://frontend.apollo.local/

${CYAN}Alternative DNS (no /etc/hosts edit):${NC}
  Use nip.io: http://frontend.$ENVOY_IP.nip.io/  (auto-resolves to the IP)
EOF
else
  cat <<EOF

${RED}MetalLB did not assign an IP. Check:${NC}
  kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway
  kubectl logs -n metallb-system deploy/controller
EOF
fi

ok "Set 4 applied. Run ./scripts/verify.sh"
