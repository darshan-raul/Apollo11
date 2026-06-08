#!/bin/bash
# Build only the frontend image with Set 3 URLs (apollo.local:30443).
set -e

SET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"

docker build -t "${REGISTRY}/frontend:latest" \
  --build-arg VITE_IDENTITY_URL="http://identity.apollo.local:30443" \
  --build-arg VITE_FLIGHT_URL="http://flight.apollo.local:30443" \
  --build-arg VITE_BOOKING_URL="http://booking.apollo.local:30443" \
  --build-arg VITE_SEARCH_URL="http://search.apollo.local:30443" \
  "${SET_DIR}/../code/frontend/"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  kind load docker-image "${REGISTRY}/frontend:latest" --name "$CLUSTER"
  echo "loaded into kind cluster '$CLUSTER'"
fi
