#!/bin/bash
# ebs-sweep.sh — Delete orphaned EBS volumes left over from cluster teardown.
#
# EKS releases a PV's underlying EBS volume on PVC deletion, but the
# `reclaimPolicy: Delete` only fires when the PV is fully released from any
# claim. If the cluster was destroyed mid-flight, the volume can end up in
# `available` state (not attached to anything) but still in your account,
# still being billed.
#
# This script lists those volumes and deletes them. Safe to re-run.
#
# Run from stages/eks: ./scripts/ebs-sweep.sh [region]
set -uo pipefail

REGION="${1:-${AWS_REGION:-us-east-1}}"
CLUSTER_NAME="${2:-${CLUSTER_NAME:-apollo11-dev}}"

GREEN='\033[0;32m'; RED='\033[0-31m'; CYAN='\033[0-36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }

step "Listing available (unattached) EBS volumes in $REGION for cluster $CLUSTER_NAME / Apollo11"
# Target ONLY volumes created for Apollo11 workloads or tagged with the cluster/project.
# This prevents accidentally deleting unrelated available volumes in the AWS account.
VOLS=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" \
            "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=apollo-airlines,apollo-airlines-apps,apollo-airlines-ui" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null || echo "")

# Also query if tagged with kubernetes.io/cluster/$CLUSTER_NAME or Project=apollo11
VOLS_CLUSTER=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" \
            "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned,shared" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null || echo "")

ALL_VOLS=$(echo "$VOLS $VOLS_CLUSTER" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

if [[ -z "$ALL_VOLS" ]]; then
  ok "no available Apollo11 EBS volumes — nothing to clean up"
  exit 0
fi

COUNT=0
DELETED=0
for vol in $ALL_VOLS; do
  COUNT=$((COUNT + 1))
  size=$(aws ec2 describe-volumes --volume-ids "$vol" --region "$REGION" --query 'Volumes[0].Size' --output text 2>/dev/null || echo "?")
  type=$(aws ec2 describe-volumes --volume-ids "$vol" --region "$REGION" --query 'Volumes[0].VolumeType' --output text 2>/dev/null || echo "?")
  echo "  $vol ($type, ${size}GiB)"
  if aws ec2 delete-volume --volume-id "$vol" --region "$REGION" >/dev/null 2>&1; then
    DELETED=$((DELETED + 1))
  fi
done

if [[ "$DELETED" -eq "$COUNT" ]]; then
  ok "deleted $DELETED/$COUNT orphaned EBS volume(s)"
else
  echo -e "${RED}deleted $DELETED/$COUNT — some volumes may have been re-attached between list and delete. Re-run this script.${NC}"
fi
