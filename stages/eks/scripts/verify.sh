#!/bin/bash
# verify.sh — Confirm Stage 2 + Stage 3 on EKS works.
#
# ~40 checks across 5 groups:
#   1. Cluster + addon health (5)
#   2. StatefulSets + PVCs + EBS PVs (15)
#   3. App Deployments + frontend (7)
#   4. NLB + Envoy Gateway (7)
#   5. End-to-end (login + DB row counts + DNS) (8)
#
# Run from stages/eks: ./scripts/verify.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$STAGE_DIR/terraform"

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-apollo11-dev}"

GREEN='\033[0;32m'; RED='\033[0-31m'; CYAN='\033[0-36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "\n${CYAN}▶ $1${NC}"; }

step "Preflight"
kubectl cluster-info >/dev/null 2>&1 || { echo "kubectl cannot reach the cluster. Run up.sh + apply-workloads.sh first."; exit 1; }
pass "cluster reachable"

# ---- 1/5 cluster + addon health ----

step "1/5 Cluster + addon health (5 checks)"
K8S_VER=$(kubectl version --short=true -o json 2>/dev/null | grep -oE '"gitVersion":"v[0-9.]+"' | head -1 | cut -d'"' -f4 | tr -d 'v')
[[ -n "$K8S_VER" ]] && pass "k8s version reported: $K8S_VER" || fail "could not read k8s version"

for addon in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver aws-load-balancer-controller; do
  status=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" --region "$REGION" --query 'addon.status' --output text 2>/dev/null || echo "")
  if [[ "$status" == "ACTIVE" ]]; then
    pass "addon $addon is ACTIVE"
  else
    fail "addon $addon status=$status (expected ACTIVE)"
  fi
done

# ---- 2/5 statefulsets + pvcs + pv ----

step "2/5 StatefulSets + PVCs + EBS PVs (15 checks)"
for sts in identity-db flight-db booking-db redis; do
  ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 1 ]]; then
    pass "statefulset/$sts ready=$ready"
  else
    fail "statefulset/$sts not ready (ready=$ready)"
  fi
done

for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  cond=$(kubectl get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$cond" == "True" ]]; then
    pass "pod/$pod Ready"
  else
    fail "pod/$pod not Ready (cond=$cond)"
  fi
done

EXPECTED_PVCS=(
  "apollo-airlines-apps:pg-data-identity-db-0"
  "apollo-airlines-apps:pg-data-flight-db-0"
  "apollo-airlines-apps:pg-data-booking-db-0"
  "apollo-airlines-apps:redis-data-redis-0"
)
for p in "${EXPECTED_PVCS[@]}"; do
  ns="${p%%:*}"; name="${p##*:}"
  phase=$(kubectl get pvc "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$phase" == "Bound" ]]; then
    pass "pvc $ns/$name Bound"
  else
    fail "pvc $ns/$name phase=$phase (expected Bound)"
  fi
done

# PVs should be EBS gp3, AZ-bound
pv_count=$(kubectl get pv --no-headers 2>/dev/null | grep -c "Bound" || echo 0)
if [[ "$pv_count" -ge 4 ]]; then
  pass "$pv_count PVs in Bound state"
else
  fail "only $pv_count PVs in Bound state (expected ≥ 4)"
fi

# Check StorageClass is the ebs-gp3 we installed
sc=$(kubectl get storageclass ebs-gp3 -o jsonpath='{.provisioner}' 2>/dev/null || echo "")
if [[ "$sc" == "ebs.csi.aws.com" ]]; then
  pass "StorageClass ebs-gp3 uses ebs.csi.aws.com provisioner"
else
  fail "StorageClass ebs-gp3 provisioner=$sc (expected ebs.csi.aws.com)"
fi

# VolumeBindingMode is WaitForFirstConsumer
vbm=$(kubectl get storageclass ebs-gp3 -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "")
if [[ "$vbm" == "WaitForFirstConsumer" ]]; then
  pass "StorageClass ebs-gp3 uses WaitForFirstConsumer"
else
  fail "StorageClass ebs-gp3 volumeBindingMode=$vbm (expected WaitForFirstConsumer)"
fi

# ---- 3/5 app deployments + frontend ----

step "3/5 App Deployments + frontend (7 checks)"
for d in identity flight booking search notification; do
  ready=$(kubectl get deploy "$d" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 2 ]]; then
    pass "deploy apollo-airlines-apps/$d ready=$ready"
  else
    fail "deploy apollo-airlines-apps/$d ready=$ready (expected ≥ 2)"
  fi
done

ready=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 2 ]]; then pass "deploy apollo-airlines-ui/frontend ready=$ready"; else fail "deploy frontend ready=$ready (expected ≥ 2)"; fi

# Image source: should be ECR (i.e., the kubelet pulled from ECR, not local cache)
# Check one pod's image reference.
img=$(kubectl get pod -n apollo-airlines-apps -l app=identity -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null | head -1 || echo "")
if [[ "$img" == *".dkr.ecr."*".amazonaws.com"* || "$img" == *".ecr."*".amazonaws.com"* ]]; then
  pass "app image is from ECR: $img"
else
  fail "app image is NOT from ECR (image=$img). Check apply-workloads.sh."
fi

# ---- 4/5 NLB + Envoy Gateway ----

step "4/5 NLB + Envoy Gateway (7 checks)"
NLB_NAME="${CLUSTER_NAME}-envoy-nlb"
NLB_STATE=$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --region "$REGION" --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "")
if [[ "$NLB_STATE" == "active" ]]; then
  pass "NLB $NLB_NAME is active"
else
  fail "NLB $NLB_NAME state=$NLB_STATE (expected active)"
fi

# At least 1 healthy target in at least 1 target group
HEALTHY_TGS=$(aws elbv2 describe-target-groups --load-balancer-arn "$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)" --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
if [[ -n "$HEALTHY_TGS" ]]; then
  HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$HEALTHY_TGS" --region "$REGION" --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' --output text 2>/dev/null | wc -l)
  if [[ "$HEALTHY" -ge 1 ]]; then
    pass "$HEALTHY healthy NLB target(s)"
  else
    fail "no healthy NLB targets"
  fi
else
  fail "could not get NLB target group"
fi

# GatewayClass + Gateway
gc=$(kubectl get gatewayclass eg -o jsonpath='{.spec.controllerName}' 2>/dev/null || echo "")
if [[ "$gc" == "gateway.envoyproxy.io/gatewayclass-controller" ]]; then
  pass "GatewayClass eg uses the right controller"
else
  fail "GatewayClass eg controllerName=$gc"
fi

prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$prog" == "True" ]]; then
  pass "Gateway apollo-gateway is Programmed"
else
  fail "Gateway apollo-gateway is not Programmed (status=$prog)"
fi

# Envoy data plane service
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$SVC" ]]; then
  pass "Envoy data plane Service exists: $SVC"
else
  fail "no Envoy data plane Service found"
fi

# HTTPRoutes
rt_count=$(kubectl get httproute -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
parent_count=$(kubectl get httproute -A -o custom-columns="P:.status.parents[*].controllerName" --no-headers 2>/dev/null | grep -c "gateway.envoyproxy.io" || echo 0)
if [[ "$rt_count" -ge 6 ]] && [[ "$parent_count" -ge 6 ]]; then
  pass "$rt_count HTTPRoutes, all $parent_count have parents"
else
  fail "only $rt_count/$parent_count HTTPRoutes have parents"
fi

# LBC's annotations on the EnvoyProxy
ep_anno=$(kubectl get envoyproxy envoyproxy-lb-config -n apollo-airlines-apps -o jsonpath='{.spec.provider.kubernetes.envoyService.annotations}' 2>/dev/null || echo "")
if [[ "$ep_anno" == *"aws-load-balancer-type"* ]]; then
  pass "EnvoyProxy has LBC annotations"
else
  fail "EnvoyProxy is missing LBC annotations (annotations=$ep_anno)"
fi

# ---- 5/5 end-to-end (NLB → Envoy → service) ----

step "5/5 End-to-end (8 checks)"
NLB_DNS=$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "")
if [[ -z "$NLB_DNS" ]]; then
  fail "no NLB DNS name; can't run end-to-end checks"
  echo
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "http://$NLB_DNS/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "NLB → Envoy → identity /healthz = 200"; else fail "NLB → Envoy → identity = $RESP (expected 200)"; fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "http://$NLB_DNS/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "NLB → Envoy → flight /api/flights = 200"; else fail "NLB → Envoy → flight = $RESP (expected 200)"; fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://$NLB_DNS/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "NLB → Envoy → frontend / = 200"; else fail "NLB → Envoy → frontend = $RESP (expected 200)"; fi

LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "http://$NLB_DNS/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through NLB → Envoy → identity returned JWT (${#TOKEN} chars)"
else
  fail "Login through NLB failed: $LOGIN_RESP"
fi

# Seed data present in DBs
u_count=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo "")
if [[ "$u_count" -ge 2 ]]; then
  pass "users table has $u_count rows (seed worked)"
else
  fail "users table has $u_count rows (expected ≥ 2)"
fi

a_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo "")
if [[ "$a_count" -ge 6 ]]; then
  pass "airports table has $a_count rows (seed worked)"
else
  fail "airports table has $a_count rows (expected ≥ 6)"
fi

f_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo "")
if [[ "$f_count" -ge 180 ]]; then
  pass "flights table has $f_count rows (seed worked)"
else
  fail "flights table has $f_count rows (expected ≥ 180)"
fi

# PVC persistence demo: insert a row, delete the pod, confirm row is still there
TEST_TABLE="apollo11_verify_$(date +%s)"
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c "CREATE TABLE IF NOT EXISTS $TEST_TABLE (id serial PRIMARY KEY, msg text); INSERT INTO $TEST_TABLE (msg) VALUES ('pre-restart');" >/dev/null 2>&1
kubectl delete pod identity-db-0 -n apollo-airlines-apps --wait=false >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/identity-db-0 -n apollo-airlines-apps --timeout=120s >/dev/null 2>&1
post_count=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -tAc "SELECT count(*) FROM $TEST_TABLE;" 2>/dev/null || echo "")
if [[ "$post_count" -ge 1 ]]; then
  pass "PVC persistence: $post_count row(s) survived pod restart"
else
  fail "PVC persistence: 0 rows after restart (EBS volume lost data!)"
fi
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c "DROP TABLE IF EXISTS $TEST_TABLE;" >/dev/null 2>&1

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
