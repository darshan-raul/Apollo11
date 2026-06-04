#!/bin/bash
set -e

CLUSTER="${CLUSTER:-apollo11}"
SERVICES="identity flight booking search notification frontend"
REGISTRY="apollo11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SKIP_KIND=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster) CLUSTER="$2"; shift 2 ;;
        --skip-kind-load) SKIP_KIND=true; shift ;;
        --help) echo "Usage: $0 [--cluster NAME] [--skip-kind-load]"; exit 1 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "=== Building Apollo Airlines images ==="
for svc in $SERVICES; do
    echo "Building $svc..."
    docker build -t "${REGISTRY}/${svc}:latest" \
        -f "${PROJECT_ROOT}/launchpad/code/${svc}/Dockerfile" \
        "${PROJECT_ROOT}/launchpad/code/${svc}/"
done

if [[ "$SKIP_KIND" == "true" ]]; then
    echo "Done (no kind load)."
    exit 0
fi

if ! kind get clusters | grep -q "^${CLUSTER}$"; then
    echo "kind cluster '$CLUSTER' not found."
    exit 0
fi

for svc in $SERVICES; do
    kind load docker-image "${REGISTRY}/${svc}:latest" --name "${CLUSTER}" 2>/dev/null || echo "  (kind load failed)"
done
echo "Done."