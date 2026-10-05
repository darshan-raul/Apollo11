#!/usr/bin/env bash
# Usage: ebs-sweep.sh [region] [cluster] [--delete]
# Dry-run by default. Deletion requires BOTH cluster ownership and an Apollo PVC namespace.
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-apollo11-dev}"
DELETE=false
POSITION=0
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE=true ;;
    --*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *)
      POSITION=$((POSITION + 1))
      case "$POSITION" in
        1) REGION="$arg" ;;
        2) CLUSTER_NAME="$arg" ;;
        *) echo 'Usage: ebs-sweep.sh [region] [cluster] [--delete]' >&2; exit 2 ;;
      esac ;;
  esac
done
[[ -n "$CLUSTER_NAME" ]] || { echo 'Cluster name must not be empty' >&2; exit 2; }
# Namespace names alone are not proof of ownership; the filters are ANDed.
VOLS=$(aws ec2 describe-volumes --region "$REGION" \
  --filters 'Name=status,Values=available' \
    "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    'Name=tag:kubernetes.io/created-for/pvc/namespace,Values=apollo-airlines,apollo-airlines-apps,apollo-airlines-ui' \
  --query 'Volumes[].VolumeId' --output text)
if [[ -z "$VOLS" || "$VOLS" == None ]]; then
  echo "No unattached volumes with proven Apollo ownership in $REGION / $CLUSTER_NAME."
  exit 0
fi
for vol in $VOLS; do
  if [[ "$DELETE" == true ]]; then
    # Recheck ownership/state immediately before each destructive operation.
    matched=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$vol" \
      --filters 'Name=status,Values=available' \
        "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
        'Name=tag:kubernetes.io/created-for/pvc/namespace,Values=apollo-airlines,apollo-airlines-apps,apollo-airlines-ui' \
      --query 'Volumes[].VolumeId' --output text)
    [[ "$matched" == "$vol" ]] || { echo "Ownership or state changed for $vol; refusing deletion" >&2; exit 1; }
    aws ec2 delete-volume --volume-id "$vol" --region "$REGION"
    echo "Deleted $vol"
  else
    echo "Would delete $vol (use --delete after reviewing ownership)."
  fi
done
