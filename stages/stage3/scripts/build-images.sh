#!/bin/bash
# Build + load all 7 service images into kind.
# Run from stages/stage3: ./scripts/build-images.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(dirname "$SCRIPT_DIR")/code"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
SERVICES="identity flight booking search notification frontend"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }

step "Checking kind cluster"
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  echo "Cluster '$CLUSTER' not found. Skipping image build/load."
  exit 0
fi

step "Building frontend (URLs: <svc>.apollo.local — MetalLB IP)"
docker build -t "${REGISTRY}/frontend:latest" \
  --build-arg VITE_IDENTITY_URL="http://identity.apollo.local" \
  --build-arg VITE_FLIGHT_URL="http://flight.apollo.local" \
  --build-arg VITE_BOOKING_URL="http://booking.apollo.local" \
  --build-arg VITE_SEARCH_URL="http://search.apollo.local" \
  "${CODE_DIR}/frontend/"
ok "frontend image built"

step "Building backend services"
for svc in $SERVICES; do
  if [[ "$svc" == "frontend" ]]; then continue; fi
  if [[ -d "${CODE_DIR}/${svc}" ]]; then
    docker build -t "${REGISTRY}/${svc}:latest" "${CODE_DIR}/${svc}/"
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "$CLUSTER"
    ok "built + loaded ${REGISTRY}/${svc}:latest"
  fi
done

step "Loading frontend image"
kind load docker-image "${REGISTRY}/frontend:latest" --name "$CLUSTER"
ok "loaded ${REGISTRY}/frontend:latest"

ok "All images built and loaded into '$CLUSTER'"
