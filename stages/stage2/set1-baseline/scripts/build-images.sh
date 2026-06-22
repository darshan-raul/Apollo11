#!/bin/bash
# Build only the frontend image with Set 1 URLs (NodePort 30083/30081/30082/30084).
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
  --build-arg VITE_IDENTITY_URL="http://localhost:30083" \
  --build-arg VITE_FLIGHT_URL="http://localhost:30081" \
  --build-arg VITE_BOOKING_URL="http://localhost:30082" \
  --build-arg VITE_SEARCH_URL="http://localhost:30084" \
  "${SET_DIR}/../code/frontend/"


