#!/bin/bash
set -e

CLUSTER="${CLUSTER:-apollo11}"
SERVICES="identity flight booking search notification frontend"
REGISTRY="apollo11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAUNCHPAD_ROOT="$(dirname "$PROJECT_ROOT")/launchpad"

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

echo "=== Building Apollo Airlines service images ==="

for svc in $SERVICES; do
    if [[ "$svc" == "frontend" ]]; then
        echo "Building $svc (with VITE_* build args for k8s)..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            --build-arg VITE_IDENTITY_URL=http://identity:8080 \
            --build-arg VITE_FLIGHT_URL=http://flight:8081 \
            --build-arg VITE_BOOKING_URL=http://booking:8082 \
            --build-arg VITE_SEARCH_URL=http://search:8083 \
            -f "${LAUNCHPAD_ROOT}/code/${svc}/Dockerfile" \
            "${LAUNCHPAD_ROOT}/code/${svc}/"
    else
        echo "Building $svc..."
        docker build -t "${REGISTRY}/${svc}:latest" \
            -f "${LAUNCHPAD_ROOT}/code/${svc}/Dockerfile" \
            "${LAUNCHPAD_ROOT}/code/${svc}/"
    fi
done

if [[ "$SKIP_KIND" == "true" ]]; then
    echo ""
    echo "Skipped loading into kind (--skip-kind-load)."
    echo ""
    echo "Done. Images built:"
    for svc in $SERVICES; do
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
    for svc in $SERVICES; do
        echo "  ${REGISTRY}/${svc}:latest"
    done
    exit 0
fi

echo ""
echo "=== Loading images into kind cluster ==="

for svc in $SERVICES; do
    echo "Loading ${REGISTRY}/${svc}:latest..."
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "${CLUSTER}" 2>/dev/null || \
        echo "  (failed to load — cluster may not be running)"
done

echo ""
echo "Done. Images loaded:"
for svc in $SERVICES; do
    echo "  ${REGISTRY}/${svc}:latest"
done