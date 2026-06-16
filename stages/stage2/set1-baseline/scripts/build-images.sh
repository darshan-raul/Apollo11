#!/bin/bash
# Build only the frontend image with Set 1 URLs (NodePort 30083/30081/30082/30084).
# Use this directly if you don't want to run apply.sh.
set -e

SET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"

docker build -t "${REGISTRY}/frontend:latest" \
  --build-arg VITE_IDENTITY_URL="http://localhost:30083" \
  --build-arg VITE_FLIGHT_URL="http://localhost:30081" \
  --build-arg VITE_BOOKING_URL="http://localhost:30082" \
  --build-arg VITE_SEARCH_URL="http://localhost:30084" \
  "${SET_DIR}/../code/frontend/"


