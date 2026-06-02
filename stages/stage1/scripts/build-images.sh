#!/bin/bash
# Build all 6 Apollo11 service images and load into kind cluster
set -e

CLUSTER="${CLUSTER:-apollo11}"
SERVICES="auth catalog circulation notification fines frontend"
REGISTRY="apollo11"

echo "=== Building Apollo11 service images ==="

# Build each service
for svc in $SERVICES; do
  echo "Building $svc..."
  docker build -t "${REGISTRY}/${svc}:latest" \
    -f "stages/liftoff/code/${svc}/Dockerfile" \
    "stages/liftoff/code/${svc}/"
done

echo ""
echo "=== Loading images into kind cluster ==="

# Load into kind
for svc in $SERVICES; do
  kind load docker-image "${REGISTRY}/${svc}:latest" --name "${CLUSTER}"
done

echo ""
echo "Done. Images loaded:"
for svc in $SERVICES; do
  echo "  ${REGISTRY}/${svc}:latest"
done