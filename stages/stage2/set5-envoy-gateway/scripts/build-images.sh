#!/bin/bash
# Build only the frontend image with Set 5 URLs (apollo.local — real IP from MetalLB).
# Use this directly if you don't want to run apply.sh.
set -e

SET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"

# --no-cache forces a fresh build. Without it, the Docker layer cache
# returns the previous image if the Dockerfile's COPY layers are
# identical — but the VITE_* build-args can change the OUTPUT (Vite
# bakes them into the JS bundle) without changing the input layers.
# Result: a silently-stale image with old URLs. The cost is one full
# build per run, which is negligible for a small frontend.
docker build --no-cache -t "${REGISTRY}/frontend:latest" \
  --build-arg VITE_IDENTITY_URL="http://identity.apollo.local" \
  --build-arg VITE_FLIGHT_URL="http://flight.apollo.local" \
  --build-arg VITE_BOOKING_URL="http://booking.apollo.local" \
  --build-arg VITE_SEARCH_URL="http://search.apollo.local" \
  "${SET_DIR}/../code/frontend/"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  kind load docker-image "${REGISTRY}/frontend:latest" --name "$CLUSTER"
  echo "loaded into kind cluster '$CLUSTER'"
  kubectl rollout restart deployment/frontend -n apollo-airlines-ui >/dev/null 2>&1
  kubectl rollout status deployment/frontend -n apollo-airlines-ui --timeout=120s >/dev/null 2>&1
  echo "frontend rolled out with fresh image"
fi
