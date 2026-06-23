#!/bin/bash
# up.sh — Provision EKS + addon stack + Envoy Gateway.
#
#   1. terraform init
#   2. terraform apply (VPC, EKS, node groups, addons, Pod Identity, LBC,
#      Envoy Gateway stack, StorageClass, ECR)
#   3. Write kubeconfig
#   4. Print the NLB DNS name when the LBC finishes provisioning it
#
# Spin-up is ~10-12 minutes:
#   - VPC + NAT Gateway:  ~1 min
#   - EKS control plane:  ~5-8 min
#   - Node groups:        ~2-3 min
#   - Addons + Envoy:     ~1-2 min
#   - LBC NLB:            ~1-2 min
#
# Run from stages/eks: ./scripts/up.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$STAGE_DIR/terraform"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-apollo11-dev}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "Preflight: aws cli + terraform"
command -v aws      >/dev/null || fail "aws cli not installed (devbox: devbox add awscli)"
command -v terraform>/dev/null || fail "terraform not installed (devbox: devbox add terraform@latest)"

# Check AWS creds are usable (doesn't print secrets).
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  fail "AWS creds not configured. Run: aws configure  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)"
fi
ok "AWS creds valid"

step "Preflight: AWS region is $REGION"
aws ec2 describe-availability-zones --region "$REGION" --query 'AvailabilityZones[0].RegionName' --output text >/dev/null \
  || fail "region $REGION not reachable"

step "1/4 terraform init"
cd "$TF_DIR"
terraform init -input=false -upgrade
ok "terraform init"

step "2/4 terraform apply (this will take ~10 minutes)"
terraform apply -auto-approve -input=false \
  -var "region=$REGION" \
  -var "cluster_name=$CLUSTER_NAME"
ok "terraform apply"

step "3/4 Write kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null
ok "kubeconfig written to ~/.kube/config"

step "4/4 Wait for the NLB to be provisioned by the AWS Load Balancer Controller"
NLB_NAME="${CLUSTER_NAME}-envoy-nlb"
echo "  Waiting for NLB '$NLB_NAME' in $REGION..."
NLB_DNS=""
for i in $(seq 1 60); do
  NLB_STATE=$(aws elbv2 describe-load-balancers \
    --names "$NLB_NAME" \
    --region "$REGION" \
    --query 'LoadBalancers[0].State.Code' \
    --output text 2>/dev/null || echo "")
  if [[ "$NLB_STATE" == "active" ]]; then
    NLB_DNS=$(aws elbv2 describe-load-balancers \
      --names "$NLB_NAME" \
      --region "$REGION" \
      --query 'LoadBalancers[0].DNSName' \
      --output text 2>/dev/null || echo "")
    NLB_SCHEME=$(aws elbv2 describe-load-balancers \
      --names "$NLB_NAME" \
      --region "$REGION" \
      --query 'LoadBalancers[0].Scheme' \
      --output text 2>/dev/null || echo "")
    break
  fi
  sleep 5
done

if [[ -z "$NLB_DNS" ]]; then
  cat <<EOF

${RED}NLB '$NLB_NAME' did not become active within 5 minutes.${NC}
Check:
  aws elbv2 describe-load-balancers --names "$NLB_NAME" --region $REGION
  kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

The cluster is up — you can still apply workloads and investigate.
EOF
  exit 1
fi
ok "NLB is active: $NLB_DNS ($NLB_SCHEME)"

cat <<EOF

${GREEN}Cluster is up.${NC}

  Cluster:    $CLUSTER_NAME  (region $REGION)
  NLB DNS:    $NLB_DNS
  NLB scheme: $NLB_SCHEME

${CYAN}Next steps:${NC}
  ./scripts/apply-workloads.sh    # deploy Apollo11 services + StatefulSets
  ./scripts/verify.sh             # 40+ checks (NLB, EBS, Envoy, app health)

${CYAN}Reach the services (add to /etc/hosts, or use nip.io):${NC}
  # /etc/hosts
  $NLB_DNS  frontend.apollo.local identity.apollo.local flight.apollo.local \\
             booking.apollo.local search.apollo.local

  # nip.io (no /etc/hosts edit)
  http://frontend.$NLB_DNS.nip.io/

  # AWS-style (no /etc/hosts edit, uses Host header via curl)
  curl -H 'Host: identity.apollo.local' http://$NLB_DNS/api/users/login \\
    -H 'Content-Type: application/json' \\
    -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
EOF
