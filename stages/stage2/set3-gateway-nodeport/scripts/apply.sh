#!/bin/bash
# Apply Set 3: Envoy Gateway API (host-based, port-forward to envoy service).
# Run from the set3-gateway-nodeport directory: ./scripts/apply.sh
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

step "0/8 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
  exit 1
fi

step "1/8 Building + loading frontend image (URLs: <svc>.apollo.local — routed via /etc/hosts + port-forward)"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  # Use unique dev port for port-forward (avoids clashing with NodePort 30080 in Set 1)
  DEV_PORT="${DEV_PORT:-8888}"
  docker build -t "${REGISTRY}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="http://identity.apollo.local:${DEV_PORT}" \
    --build-arg VITE_FLIGHT_URL="http://flight.apollo.local:${DEV_PORT}" \
    --build-arg VITE_BOOKING_URL="http://booking.apollo.local:${DEV_PORT}" \
    --build-arg VITE_SEARCH_URL="http://search.apollo.local:${DEV_PORT}" \
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

step "4/8 Apps + infra (10 components, ClusterIP)"
kubectl apply -f "$K8S_DIR/apps/" --recursive

step "5/8 Init jobs (3 DBs)"
kubectl apply -f "$K8S_DIR/jobs/"

step "6/8 Envoy Gateway install (CRDs + controller)"
# install.yaml is ~1.5MB; client-side apply would exceed the 256KB
# last-applied-configuration annotation limit. Use --server-side.
kubectl apply --server-side -f "$K8S_DIR/gateway/00-envoy-gateway-install.yaml"

# GatewayClass isn't in the install.yaml manifest as a resource — it's only
# in the ConfigMap data. Create it explicitly.
kubectl apply -f "$K8S_DIR/gateway/00a-gatewayclass.yaml"

step "7/8 Gateway + HTTPRoutes + cross-namespace ReferenceGrant"
kubectl apply -f "$K8S_DIR/gateway/01-gateway.yaml"
kubectl apply -f "$K8S_DIR/gateway/01a-referencegrant.yaml"
kubectl apply -f "$K8S_DIR/gateway/02-httproute-identity.yaml"
kubectl apply -f "$K8S_DIR/gateway/03-httproute-flight.yaml"
kubectl apply -f "$K8S_DIR/gateway/04-httproute-booking.yaml"
kubectl apply -f "$K8S_DIR/gateway/05-httproute-search.yaml"
kubectl apply -f "$K8S_DIR/gateway/06-httproute-notification.yaml"
kubectl apply -f "$K8S_DIR/gateway/07-httproute-frontend.yaml"

echo "  Waiting for Envoy Gateway to Program the Gateway..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  if [[ "$prog" == "True" ]]; then
    ok "Gateway is Programmed"
    break
  fi
  sleep 5
done

# Patch the auto-created Envoy Service from LoadBalancer to ClusterIP.
# In kind, LoadBalancer Services never get an IP. We use port-forward instead.
# (Set 4 uses MetalLB so the Service can stay LoadBalancer and get a real IP.)
echo "  Patching auto-created Envoy Service to ClusterIP..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$SVC" ]]; then
    kubectl patch svc "$SVC" -n envoy-gateway-system --type=json \
      -p '[{"op":"replace","path":"/spec/type","value":"ClusterIP"}]' 2>&1 | head -1
    ok "Patched $SVC to ClusterIP"
    break
  fi
  sleep 5
done

step "8/8 Port-forward + /etc/hosts reminder"
cat <<EOF

${GREEN}Start port-forward in a separate terminal:${NC}
  kubectl port-forward -n apollo-airlines-apps svc/apollo-gateway 8888:80

${GREEN}Add these lines to your /etc/hosts:${NC}
  127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \\
              booking.apollo.local search.apollo.local

Then test with:
  curl -H 'Host: identity.apollo.local' http://localhost:8888/healthz
  open http://frontend.apollo.local:8888

${CYAN}Why port-forward instead of NodePort?${NC}
  Envoy Gateway v1.2.x doesn't expose spec.infrastructure.serviceOverride.
  Its auto-created Service is ClusterIP. We use port-forward to access it
  from the host. Set 4 uses MetalLB so the Gateway gets a real IP.
EOF

ok "Set 3 applied. After starting port-forward, run ./scripts/verify.sh"
