#!/bin/bash
# apply-workloads.sh — Deploy the Apollo11 services to the EKS cluster.
#
# This is a port of stages/stage3/scripts/apply.sh for EKS. Differences from
# the kind version:
#   1. Image delivery is via ECR (docker push to the new repos), not
#      `kind load docker-image`.
#   2. The MetalLB install step is removed (handled by the AWS Load Balancer
#      Controller + NLB).
#   3. The Envoy install step is removed (handled by the Terraform
#      kubectl_manifest applies).
#   4. The frontend's VITE_* URLs point at the NLB DNS (or use nip.io),
#      not a MetalLB IP.
#
# The 10-step ordering matches stages/stage3/scripts/apply.sh.
#
# Run from stages/eks: ./scripts/apply-workloads.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$STAGE_DIR/terraform"
STAGE3_DIR="$STAGE_DIR/../stage3"

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-apollo11-dev}"
SERVICES="identity flight booking search notification frontend"
SKIP_PUSH="${SKIP_PUSH:-0}"  # 1 = skip docker build+push (use existing images)

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ---- preflight ----

step "Preflight: kubectl can reach the cluster"
kubectl cluster-info >/dev/null 2>&1 || fail "kubectl cannot reach a cluster. Did you run up.sh?"
ok "cluster reachable"

step "Preflight: ECR registry from terraform output"
cd "$TF_DIR"
ECR_REGISTRY=$(terraform output -raw ecr_registry)
[[ -n "$ECR_REGISTRY" ]] || fail "could not read ecr_registry from terraform output. Did you run terraform apply?"
ok "ECR registry: $ECR_REGISTRY"

step "Preflight: docker"
command -v docker >/dev/null || fail "docker not installed"
ok "docker present"

# ---- 1/10 build + push images ----

step "1/10 Build + push 6 service images to ECR"
if [[ "$SKIP_PUSH" == "1" ]]; then
  echo "  SKIP_PUSH=1; skipping build+push"
else
  # ECR login (token is valid for 12h)
  aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null
  ok "ECR login"

  # The frontend VITE_* URLs point at the NLB. We don't know the NLB DNS at
  # build time here, so we use the *.nip.io convention: any client can reach
  # identity.${NLB_DNS}.nip.io without /etc/hosts editing. The frontend will
  # call http://identity.${NLB}.nip.io/.../ — nip.io resolves ${NLB}.nip.io
  # to that IP for free.
  #
  # Alternative: hardcode *.apollo.local and use /etc/hosts (or a real DNS
  # zone). Set FRONTEND_HOST_SUFFIX to override.
  HOST_SUFFIX="${FRONTEND_HOST_SUFFIX:-.nip.io}"
  NLB_FQDN="NLB${HOST_SUFFIX}"
  echo "  Frontend VITE_* URLs use $NLB_FQDN pattern"

  # Frontend: Vite bakes VITE_* into the JS bundle at build time.
  docker build --no-cache -t "${ECR_REGISTRY}/${CLUSTER_NAME}/frontend:latest" \
    --build-arg VITE_IDENTITY_URL="http://identity${HOST_SUFFIX}" \
    --build-arg VITE_FLIGHT_URL="http://flight${HOST_SUFFIX}" \
    --build-arg VITE_BOOKING_URL="http://booking${HOST_SUFFIX}" \
    --build-arg VITE_SEARCH_URL="http://search${HOST_SUFFIX}" \
    "${STAGE3_DIR}/code/frontend/"
  docker push "${ECR_REGISTRY}/${CLUSTER_NAME}/frontend:latest"
  ok "frontend image pushed"

  for svc in $SERVICES; do
    if [[ "$svc" == "frontend" ]]; then continue; fi
    if [[ -f "${STAGE3_DIR}/code/${svc}/Dockerfile" ]]; then
      docker build -t "${ECR_REGISTRY}/${CLUSTER_NAME}/${svc}:latest" "${STAGE3_DIR}/code/${svc}/"
      docker push "${ECR_REGISTRY}/${CLUSTER_NAME}/${svc}:latest"
      ok "pushed ${ECR_REGISTRY}/${CLUSTER_NAME}/${svc}:latest"
    else
      echo "  ${STAGE3_DIR}/code/${svc}/Dockerfile not found, skipping"
    fi
  done
fi

# ---- 2/10 namespaces + config + secrets ----

step "2/10 Namespaces + config + secrets (from stages/stage3/k8s/config/)"
kubectl apply -f "${STAGE3_DIR}/k8s/config/"
ok "namespaces + configmap + secret applied"

# ---- 3/10 serviceaccounts ----

step "3/10 ServiceAccounts (13, from stages/stage3/k8s/serviceaccounts/)"
kubectl apply -f "${STAGE3_DIR}/k8s/serviceaccounts/"
ok "serviceaccounts applied"

# NetworkPolicies are reference only — Calico/Cilium would enforce them, but
# the VPC CNI does not. Document but do not apply.

# ---- 4/10 apps + infra ----

# The Stage 3 manifests have the apollo11/* image tag. We patch the
# imagePullPolicy on the fly (in-memory via sed + kubectl apply) so the
# kubelet pulls from ECR instead of looking in a local cache. The ECR
# pull is gated by the node IAM role's AmazonEC2ContainerRegistryReadOnly
# (attached in node-groups.tf).
step "4/10 Apply stages/stage3/k8s/apps/ with image tags rewritten to ECR"
APP_SRC="${STAGE3_DIR}/k8s/apps"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Rewrite apollo11/identity:latest → <ECR_REGISTRY>/<CLUSTER_NAME>/identity:latest
for f in $(find "$APP_SRC" -name '*.yaml'); do
  rel="${f#$APP_SRC/}"
  out="$TMP_DIR/$rel"
  mkdir -p "$(dirname "$out")"
  sed -E "s#(image:[[:space:]]*)apollo11/([a-z]+):latest#\\1${ECR_REGISTRY}/${CLUSTER_NAME}/\\2:latest#g" "$f" > "$out"
done
kubectl apply -f "$TMP_DIR" --recursive
ok "apps applied with ECR image tags"

# ---- 5/10 wait for StatefulSets ----

step "5/10 Wait for StatefulSet pods to be Ready"
for sts in identity-db flight-db booking-db redis; do
  echo "  Waiting for statefulset/$sts..."
  if ! kubectl rollout status statefulset/"$sts" -n apollo-airlines-apps --timeout=300s 2>/dev/null; then
    fail "statefulset/$sts did not become Ready within 300s. Check: kubectl describe sts $sts -n apollo-airlines-apps"
  fi
  ok "statefulset/$sts ready"
done

for db in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  echo "  Waiting for pod/$db to be Ready..."
  if ! kubectl wait --for=condition=Ready pod/"$db" -n apollo-airlines-apps --timeout=120s >/dev/null 2>&1; then
    fail "pod/$db not Ready within 120s"
  fi
  ok "pod/$db Ready"
done

# ---- 6/10 seed jobs ----

step "6/10 Seed jobs (3, idempotent ON CONFLICT DO NOTHING)"
kubectl apply -f "${STAGE3_DIR}/k8s/jobs/"
ok "seed jobs applied"

step "7/10 Wait for seed jobs to succeed"
for j in seed-identity-db seed-flight-db seed-booking-db; do
  echo "  Waiting for job/$j..."
  if ! kubectl wait --for=condition=Complete job/"$j" -n apollo-airlines-apps --timeout=180s >/dev/null 2>&1; then
    echo -e "${RED}Job $j did not complete. Logs:${NC}"
    kubectl logs -n apollo-airlines-apps -l app="$j" --tail=20
    fail "job/$j failed"
  fi
  ok "job/$j succeeded"
done

# ---- 8/10 ENVOY PROXY + GATEWAY + HTTPROUTES ----
# Terraform already applied these. We just wait for the Gateway to be
# Programmed (i.e., the Envoy data plane Service has an NLB IP/hostname).
step "8/10 Wait for Envoy Gateway 'apollo-gateway' to be Programmed"
for i in $(seq 1 60); do
  prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  if [[ "$prog" == "True" ]]; then
    ok "Gateway is Programmed"
    break
  fi
  sleep 5
done

if [[ "$prog" != "True" ]]; then
  fail "Gateway did not become Programmed within 5 minutes. Check: kubectl describe gateway apollo-gateway -n apollo-airlines-apps"
fi

# ---- 9/10 wait for NLB ----

step "9/10 Wait for NLB hostname in the Envoy data plane Service"
NLB_HOSTNAME=""
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$ENVOY_SVC" ]]; then
  fail "no Envoy data plane Service found. Check: kubectl get svc -n envoy-gateway-system"
fi
for i in $(seq 1 60); do
  NLB_HOSTNAME=$(kubectl get svc "$ENVOY_SVC" -n envoy-gateway-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [[ -n "$NLB_HOSTNAME" ]]; then
    ok "NLB hostname: $NLB_HOSTNAME"
    break
  fi
  sleep 5
done
[[ -n "$NLB_HOSTNAME" ]] || fail "no NLB hostname assigned to $ENVOY_SVC after 5 minutes"

# ---- 10/10 print the URLs ----

cat <<EOF

${GREEN}All workloads applied.${NC}

  NLB hostname: $NLB_HOSTNAME

${CYAN}Test (no /etc/hosts edit, uses nip.io or AWS Host header):${NC}
  curl -H 'Host: identity.apollo.local' http://$NLB_HOSTNAME/api/users/login \\
    -H 'Content-Type: application/json' \\
    -d '{"email":"admin@apolloairlines.com","password":"admin123"}'

${CYAN}Or with /etc/hosts:${NC}
  echo "$NLB_HOSTNAME  frontend.apollo.local identity.apollo.local flight.apollo.local \\
                       booking.apollo.local search.apollo.local" >> /etc/hosts
  curl http://identity.apollo.local/api/users/login \\
    -H 'Content-Type: application/json' \\
    -d '{"email":"admin@apolloairlines.com","password":"admin123"}'

Run ./scripts/verify.sh to confirm 40+ checks pass.
EOF
