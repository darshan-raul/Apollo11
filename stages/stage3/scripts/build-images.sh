#!/usr/bin/env bash

set -euo pipefail

CLUSTER="${CLUSTER:-apollo11}"
SERVICES=(identity flight booking search notification frontend)
REGISTRY="apollo11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 [--cluster NAME] [--skip-kind-load]"
    echo "  --cluster NAME      kind cluster name (default: apollo11)"
    echo "  --skip-kind-load    build images only, skip loading into kind"
    exit 1
}

SKIP_KIND=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster) CLUSTER="$2"; shift 2 ;;
        --skip-kind-load) SKIP_KIND=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "=== Building Apollo Airlines service images (Stage 3) ==="

for svc in "${SERVICES[@]}"; do
    if [[ "$svc" == "frontend" ]]; then
        echo "Building $svc..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            --build-arg VITE_IDENTITY_URL=https://identity.apollo.local \
            --build-arg VITE_FLIGHT_URL=https://flight.apollo.local \
            --build-arg VITE_BOOKING_URL=https://booking.apollo.local \
            --build-arg VITE_SEARCH_URL=https://search.apollo.local \
            -f "${STAGE_DIR}/code/${svc}/Dockerfile" \
            "${STAGE_DIR}/code/${svc}/"
    else
        echo "Building $svc..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            -f "${STAGE_DIR}/code/${svc}/Dockerfile" \
            "${STAGE_DIR}/code/${svc}/"
    fi
done

if [[ "$SKIP_KIND" == "true" ]]; then
    echo ""
    echo "Skipped loading into kind (--skip-kind-load)."
    exit 0
fi

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
    echo ""
    echo "kind cluster '${CLUSTER}' not found. Skipping image load."
    exit 0
fi

echo ""
echo "=== Loading images into kind cluster '${CLUSTER}' ==="

for svc in "${SERVICES[@]}"; do
    echo "Loading ${REGISTRY}/${svc}:latest..."
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "${CLUSTER}"
done

echo ""
echo "Done. All images loaded into kind cluster '${CLUSTER}'."
