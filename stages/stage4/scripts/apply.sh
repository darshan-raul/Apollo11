#!/bin/bash
# Apply Stage 4: probes (startup/live/ready), resource limits (Guaranteed
# QoS), PodDisruptionBudgets, and graceful SIGTERM shutdown, on top of
# Stage 3's StatefulSets + Stage 2's set-4 access stack (Envoy Gateway
# + MetalLB).
# Run from stages/stage4: ./scripts/apply.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$STAGE_DIR/k8s"
CODE_DIR="$STAGE_DIR/code"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
SERVICES="identity flight booking search notification frontend"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/10 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
ok "cluster reachable"

step "1/10 Building + loading app images"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  # Frontend: same VITE_* URLs as Stage 2 set 4 (MetalLB gives a real IP).
  docker build -t "${REGISTRY}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="http://identity.apollo.local" \
    --build-arg VITE_FLIGHT_URL="http://flight.apollo.local" \
    --build-arg VITE_BOOKING_URL="http://booking.apollo.local" \
    --build-arg VITE_SEARCH_URL="http://search.apollo.local" \
    "${CODE_DIR}/frontend/"
  ok "frontend image built"

  for svc in $SERVICES; do
    if [[ -f "${CODE_DIR}/${svc}/Dockerfile" ]]; then
      docker build -t "${REGISTRY}/${svc}:latest" "${CODE_DIR}/${svc}/"
      kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER"
      ok "loaded ${REGISTRY}/${svc}:latest"
    fi
  done
else
  echo "  Cluster '$CLUSTER' is not a kind cluster, skipping image build/load"
fi

step "2/10 Namespaces + config + secrets"
kubectl apply -f "$K8S_DIR/config/"

step "3/10 ServiceAccounts"
kubectl apply -f "$K8S_DIR/serviceaccounts/"

# NetworkPolicies are reference only — kindnet does NOT enforce them.

step "4/10 Apps (6 Deployments + 4 StatefulSets + 4 headless SVCs + 4 ClusterIP SVCs) + PodDisruptionBudgets"
kubectl apply -f "$K8S_DIR/apps/" --recursive
# Stage 4: PodDisruptionBudgets for booking and frontend. Applied here
# (after the Deployments exist) so the PDB selector can match them.
kubectl apply -f "$K8S_DIR/pdb/"

step "5/10 Waiting for StatefulSet pods to be Ready (schema runs in init container)"
# The init container in each DB pod waits for `pg_isready` and then runs init.sql.
# We block until the StatefulSet reports readyReplicas==replicas.
for sts in identity-db flight-db booking-db redis; do
  echo "  Waiting for statefulset/$sts..."
  if ! kubectl rollout status statefulset/"$sts" -n apollo-airlines-apps --timeout=180s 2>/dev/null; then
    fail "statefulset/$sts did not become Ready within 180s"
  fi
  ok "statefulset/$sts ready"
done

# Pods must be Ready (not just Running) before we run seed jobs.
for db in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  echo "  Waiting for pod/$db to be Ready..."
  if ! kubectl wait --for=condition=Ready pod/"$db" -n apollo-airlines-apps --timeout=60s >/dev/null 2>&1; then
    fail "pod/$db not Ready within 60s"
  fi
  ok "pod/$db Ready"
done

step "6/10 Seed jobs (3 data-only, idempotent ON CONFLICT DO NOTHING)"
kubectl apply -f "$K8S_DIR/jobs/"

step "7/10 Waiting for seed jobs to succeed"
for j in seed-identity-db seed-flight-db seed-booking-db; do
  echo "  Waiting for job/$j..."
  if ! kubectl wait --for=condition=Complete job/"$j" -n apollo-airlines-apps --timeout=120s >/dev/null 2>&1; then
    echo -e "${RED}Job $j did not complete. Logs:${NC}"
    kubectl logs -n apollo-airlines-apps -l app="$j" --tail=20
    fail "job/$j failed"
  fi
  ok "job/$j succeeded"
done

step "8/10 MetalLB install + IP pool + L2 advertisement"
kubectl apply --server-side --force-conflicts -f "$K8S_DIR/metallb/00-metallb-native.yaml" 2>&1 | tail -3
echo "  Waiting for MetalLB controller..."
for i in $(seq 1 30); do
  if kubectl get pods -n metallb-system -l component=controller --no-headers 2>/dev/null | grep -q "1/1"; then
    ok "MetalLB controller ready"
    break
  fi
  sleep 5
done
kubectl apply -f "$K8S_DIR/metallb/01-ip-pool.yaml"
ok "MetalLB IPAddressPool + L2Advertisement applied"

step "9/10 Envoy Gateway install + GatewayClass + Gateway + HTTPRoutes"
kubectl apply --server-side -f "$K8S_DIR/gateway/00-envoy-gateway-install.yaml" 2>&1 | tail -3
kubectl apply -f "$K8S_DIR/gateway/00a-gatewayclass.yaml"
kubectl apply -f "$K8S_DIR/gateway/01-gateway.yaml"
kubectl apply -f "$K8S_DIR/gateway/01a-referencegrant.yaml"
kubectl apply -f "$K8S_DIR/gateway/02-httproute-identity.yaml"
kubectl apply -f "$K8S_DIR/gateway/03-httproute-flight.yaml"
kubectl apply -f "$K8S_DIR/gateway/04-httproute-booking.yaml"
kubectl apply -f "$K8S_DIR/gateway/05-httproute-search.yaml"
kubectl apply -f "$K8S_DIR/gateway/06-httproute-notification.yaml"
kubectl apply -f "$K8S_DIR/gateway/07-httproute-frontend.yaml"

echo "  Waiting for Gateway to be Programmed..."
for i in $(seq 1 30); do
  prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  if [[ "$prog" == "True" ]]; then
    ok "Gateway is Programmed"
    break
  fi
  sleep 5
done

step "10/10 Waiting for MetalLB to assign LoadBalancer IP"
ENVOY_IP=""
for i in $(seq 1 24); do
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

${CYAN}Stage 3 new: verify PVCs and persistent data${NC}
  kubectl get pvc -n apollo-airlines-apps
  kubectl get statefulset -n apollo-airlines-apps
  kubectl exec -n apollo-airlines-apps identity-db-0 -- psql -U postgres -d identity -c 'SELECT count(*) FROM users;'
EOF
else
  cat <<EOF

${RED}MetalLB did not assign an IP. Check:${NC}
  kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway
  kubectl logs -n metallb-system deploy/controller
EOF
fi

ok "Stage 3 applied. Run ./scripts/verify.sh"
