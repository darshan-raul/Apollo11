#!/bin/bash
# down.sh — Tear down EKS, ECR, VPC, all Apollo11 resources.
#
# Order matters:
#   1. Delete app workloads (kubectl). This drops the Gateway + HTTPRoutes
#      first, then the StatefulSets, then the namespaces. The HTTPRoute
#      parent status on the Gateway must be cleared before the Gateway
#      can be deleted, otherwise the LBC will not release the NLB ENIs.
#   2. Uninstall Envoy Gateway (kubectl_manifest removal in TF).
#   3. Uninstall AWS Load Balancer Controller (Helm release removal in TF).
#   4. Destroy the rest of the cluster (VPC, IAM, node groups, addons).
#   5. Sweep orphaned EBS volumes + ENIs (the cluster SG sometimes
#      leaves cross-AZ ENIs behind for ~10 minutes).
#
# Run from stages/eks: ./scripts/down.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$STAGE_DIR/terraform"
STAGE3_DIR="$STAGE_DIR/../stage3"

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-apollo11-dev}"
PURGE_ECR="${PURGE_ECR:-0}"  # 1 = also delete ECR repos + images

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0-31m'; NC='\033[0m'
step()  { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "Preflight"
command -v aws       >/dev/null || fail "aws cli not installed"
command -v terraform >/dev/null || fail "terraform not installed"
aws sts get-caller-identity >/dev/null 2>&1 || fail "AWS creds not configured"
ok "tools + creds present"

# ---- 1/7 app workloads (kubectl) ----

step "1/7 Delete app namespaces (apollo-airlines-apps, apollo-airlines-ui)"
if kubectl cluster-info >/dev/null 2>&1; then
  # Best-effort: runs even if the cluster is unreachable.
  for ns in apollo-airlines-apps apollo-airlines-ui; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      kubectl delete ns "$ns" --wait=false 2>&1 | tail -1 || true
      ok "deleted namespace $ns (async)"
    else
      echo "  namespace $ns already gone"
    fi
  done
else
  echo "  kubectl cannot reach the cluster (already gone or credentials stale). Skipping namespace deletion."
fi

# ---- 2/7 uninstall Envoy Gateway + LBC (TF) ----

step "2/7 Uninstall Envoy Gateway stack (kubectl_manifest resources)"
cd "$TF_DIR"
# Target the gateway/ module's resources. They reference the vendored yaml files.
terraform apply -destroy -auto-approve -input=false \
  -target 'kubectl_manifest.httproutes' \
  -target 'kubectl_manifest.reference_grant' \
  -target 'kubectl_manifest.gateway' \
  -target 'kubectl_manifest.envoyproxy_lb_config' \
  -target 'kubectl_manifest.gatewayclass' \
  -target 'kubectl_manifest.envoy_gateway_install' \
  -var "region=$REGION" \
  -var "cluster_name=$CLUSTER_NAME" 2>&1 | tail -20 || true
ok "Envoy Gateway stack uninstalled"

# ---- 3/7 uninstall LBC (Helm release) ----

step "3/7 Uninstall AWS Load Balancer Controller (Helm release)"
terraform apply -destroy -auto-approve -input=false \
  -target 'helm_release.aws_load_balancer_controller' \
  -var "region=$REGION" \
  -var "cluster_name=$CLUSTER_NAME" 2>&1 | tail -20 || true
ok "LBC Helm release removed (the NLB may take 30-60s to actually delete)"

# Wait for the NLB to actually disappear. Otherwise the next apply's
# security group dependencies will block.
NLB_NAME="${CLUSTER_NAME}-envoy-nlb"
echo "  Waiting for NLB '$NLB_NAME' to be removed..."
for i in $(seq 1 60); do
  state=$(aws elbv2 describe-load-balancers \
    --names "$NLB_NAME" \
    --region "$REGION" \
    --query 'LoadBalancers[0].State.Code' \
    --output text 2>/dev/null || echo "")
  if [[ -z "$state" ]]; then
    ok "NLB is gone"
    break
  fi
  sleep 5
done

# ---- 4/7 terraform destroy (the rest) ----

step "4/7 terraform destroy (cluster, node groups, addons, VPC, ECR, IAM)"
terraform destroy -auto-approve -input=false \
  -var "region=$REGION" \
  -var "cluster_name=$CLUSTER_NAME" 2>&1 | tail -40
ok "terraform destroy complete"

# ---- 5/7 ECR purge (optional) ----

step "5/7 ECR purge (PURGE_ECR=$PURGE_ECR)"
if [[ "$PURGE_ECR" == "1" ]]; then
  for svc in identity flight booking search notification frontend; do
    repo="${CLUSTER_NAME}/${svc}"
    if aws ecr describe-repositories --repository-names "$repo" --region "$REGION" >/dev/null 2>&1; then
      aws ecr delete-repository --repository-name "$repo" --region "$REGION" --force >/dev/null 2>&1 || true
      ok "deleted ECR repo $repo"
    fi
  done
else
  echo "  Skipping ECR purge (set PURGE_ECR=1 to force-delete repos)"
fi

# ---- 6/7 sweep orphaned EBS volumes ----

step "6/7 Sweep orphaned EBS volumes (released PVs)"
./scripts/ebs-sweep.sh || true

# ---- 7/7 sweep orphaned ENIs ----

step "7/7 Sweep orphaned cluster ENIs"
ENI_COUNT=0
DELETED=0
for eni in $(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters "Name=description,Values=*${CLUSTER_NAME}*" \
  --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
  --output text 2>/dev/null || echo ""); do
  if [[ -n "$eni" ]]; then
    ENI_COUNT=$((ENI_COUNT + 1))
    if aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" >/dev/null 2>&1; then
      DELETED=$((DELETED + 1))
    fi
  fi
done
ok "swept $DELETED/$ENI_COUNT cluster ENIs (some will be cleaned up by AWS within ~10 min)"

cat <<EOF

${GREEN}Tear down complete.${NC}

${CYAN}Cost sanity check (should be ~\$0/mo for the resources you just destroyed):${NC}
  aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available \\
    --query 'Volumes[].VolumeId' --output text
  aws elbv2 describe-load-balancers --region $REGION \\
    --query 'LoadBalancers[?contains(LoadBalancerName, `${CLUSTER_NAME}`)].LoadBalancerArn' --output text
  aws ec2 describe-nat-gateways --region $REGION \\
    --filter Name=state,Values=available \\
    --query 'NatGateways[?contains(NatGatewayAddresses[0].AllocationId, `eipalloc`)].NatGatewayId' --output text

${CYAN}You are still being charged for any of the above that show up.${NC}
EOF
