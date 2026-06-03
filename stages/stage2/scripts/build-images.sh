#!/bin/bash
# Build all 6 Apollo11 service images for stage2 and load into kind cluster
set -e

CLUSTER="${CLUSTER:-apollo11}"
SERVICES="auth catalog circulation notification fines frontend"
REGISTRY="apollo11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

echo "=== Building Apollo11 service images (stage2) ==="

for svc in $SERVICES; do
    echo "Building $svc..."
    docker build -t "${REGISTRY}/${svc}:latest" \
        -f "${PROJECT_ROOT}/code/${svc}/Dockerfile" \
        "${PROJECT_ROOT}/code/${svc}/"
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

# Check if kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
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