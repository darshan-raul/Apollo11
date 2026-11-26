#!/usr/bin/env bash

set -euo pipefail

CLUSTER="${CLUSTER:-apollo11}"
SERVICES=(identity flight booking search notification frontend)
REGISTRY="apollo11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    local code="${1:-0}"
    echo "Usage: $0 [--cluster NAME] [--skip-kind-load]"
    echo "  --cluster NAME      kind cluster name (default: apollo11)"
    echo "  --skip-kind-load    build images only, skip loading into kind"
    exit "${code}"
}

SKIP_KIND=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            [[ $# -ge 2 ]] || { echo "Missing value for --cluster" >&2; usage 2 >&2; }
            CLUSTER="$2"
            shift 2
            ;;
        --skip-kind-load) SKIP_KIND=true; shift ;;
        --help|-h) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 >&2 ;;
    esac
done

echo "=== Building Apollo Airlines service images ==="

for svc in "${SERVICES[@]}"; do
    if [[ "$svc" == "frontend" ]]; then
        echo "Building $svc (ClusterIP + port-forward URLs)..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            --build-arg VITE_IDENTITY_URL=http://localhost:8080 \
            --build-arg VITE_FLIGHT_URL=http://localhost:8081 \
            --build-arg VITE_BOOKING_URL=http://localhost:8082 \
            --build-arg VITE_SEARCH_URL=http://localhost:8083 \
            -f "${PROJECT_ROOT}/code/${svc}/Dockerfile" \
            "${PROJECT_ROOT}/code/${svc}/"
    else
        echo "Building $svc..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            -f "${PROJECT_ROOT}/code/${svc}/Dockerfile" \
            "${PROJECT_ROOT}/code/${svc}/"
    fi
done

if [[ "$SKIP_KIND" == "true" ]]; then
    echo ""
    echo "Skipped loading into kind (--skip-kind-load)."
    echo ""
    echo "Done. Images built:"
    for svc in "${SERVICES[@]}"; do
        echo "  ${REGISTRY}/${svc}:latest"
    done
    exit 0
fi

if ! kind get clusters | grep -q "^${CLUSTER}$"; then
    echo ""
    echo "kind cluster '${CLUSTER}' not found. Skipping image load."
    echo "Run: kind create cluster --name ${CLUSTER}"
    echo ""
    echo "Done. Images built:"
    for svc in "${SERVICES[@]}"; do
        echo "  ${REGISTRY}/${svc}:latest"
    done
    exit 0
fi

echo ""
echo "=== Loading images into kind cluster ==="

for svc in "${SERVICES[@]}"; do
    echo "Loading ${REGISTRY}/${svc}:latest..."
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "${CLUSTER}"
done

echo ""
echo "Done. Images loaded:"
for svc in "${SERVICES[@]}"; do
    echo "  ${REGISTRY}/${svc}:latest"
done
