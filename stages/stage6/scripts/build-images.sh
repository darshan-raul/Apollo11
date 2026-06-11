#!/bin/bash
# Build all 6 Apollo Airlines service images + frontend.
#
# Default tag is `latest` (matches the Helm chart default and the kustomize
# base). The frontend image is rebuilt with the VITE_* URLs from the chart's
# values.yaml so the rendered SPA and the HTTPRoute hostnames never drift.
#
#   ./scripts/build-images.sh                # build all 6 + frontend, load to kind
#   ./scripts/build-images.sh --skip-load    # build only
#   ./scripts/build-images.sh --tag v1.2.3   # pin all images to a tag
#   ./scripts/build-images.sh --cluster foo  # target a specific kind cluster
set -euo pipefail

CLUSTER="${CLUSTER:-apollo11}"
REGISTRY="apollo11"
TAG="latest"
SKIP_KIND_LOAD=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CODE_DIR="$STAGE_DIR/code"
CHART_DIR="$STAGE_DIR/helm/apollo11"

usage() {
    cat <<EOF
Usage: $0 [--tag TAG] [--cluster NAME] [--skip-load]

Options:
  --tag TAG         Image tag to apply to all 6 services (default: latest)
  --cluster NAME    kind cluster name to load images into (default: apollo11)
  --skip-load       Build only; skip loading images into kind
  --help            Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)        TAG="$2"; shift 2 ;;
        --cluster)    CLUSTER="$2"; shift 2 ;;
        --skip-load)  SKIP_KIND_LOAD=true; shift ;;
        --help)       usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

SERVICES="identity flight booking search notification"
ALL_SERVICES="identity flight booking search notification frontend"

# Extract VITE_* URLs from the Helm chart's values.yaml so the frontend
# image and the HTTPRoutes never drift.
extract_vite_url() {
    local key="$1"
    awk -F'"' -v k="VITE_${key}_URL" '
        $0 ~ "    "k":" { gsub(/^ +/, "", $2); print $2; exit }
    ' "$CHART_DIR/values.yaml"
}

VITE_IDENTITY_URL=$(extract_vite_url IDENTITY)
VITE_FLIGHT_URL=$(extract_vite_url FLIGHT)
VITE_BOOKING_URL=$(extract_vite_url BOOKING)
VITE_SEARCH_URL=$(extract_vite_url SEARCH)

echo "=== Building Apollo Airlines service images (stage5) — tag: $TAG ==="

# Backend services
for svc in $SERVICES; do
    if [[ -d "$CODE_DIR/$svc" ]]; then
        echo "  Building ${REGISTRY}/${svc}:${TAG}..."
        docker build \
            -t "${REGISTRY}/${svc}:${TAG}" \
            -f "$CODE_DIR/$svc/Dockerfile" \
            "$CODE_DIR/$svc/"
    else
        echo "  WARNING: $CODE_DIR/$svc not found — skipping"
    fi
done

# Frontend (VITE_* baked in at build time)
if [[ -d "$CODE_DIR/frontend" ]]; then
    echo "  Building ${REGISTRY}/frontend:${TAG}..."
    echo "    VITE_IDENTITY_URL=$VITE_IDENTITY_URL"
    echo "    VITE_FLIGHT_URL=$VITE_FLIGHT_URL"
    echo "    VITE_BOOKING_URL=$VITE_BOOKING_URL"
    echo "    VITE_SEARCH_URL=$VITE_SEARCH_URL"
    docker build \
        -t "${REGISTRY}/frontend:${TAG}" \
        --build-arg "VITE_IDENTITY_URL=$VITE_IDENTITY_URL" \
        --build-arg "VITE_FLIGHT_URL=$VITE_FLIGHT_URL" \
        --build-arg "VITE_BOOKING_URL=$VITE_BOOKING_URL" \
        --build-arg "VITE_SEARCH_URL=$VITE_SEARCH_URL" \
        -f "$CODE_DIR/frontend/Dockerfile" \
        "$CODE_DIR/frontend/"
fi

if [[ "$SKIP_KIND_LOAD" == "true" ]]; then
    echo ""
    echo "Skipped loading into kind (--skip-load)."
    exit 0
fi

# Load into kind
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
    echo ""
    echo "kind cluster '${CLUSTER}' not found. Skipping image load."
    echo "Run: kind create cluster --name ${CLUSTER}"
    exit 0
fi

echo ""
echo "=== Loading images into kind cluster '$CLUSTER' ==="
for svc in $ALL_SERVICES; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${REGISTRY}/${svc}:${TAG}$"; then
        kind load docker-image "${REGISTRY}/${svc}:${TAG}" --name "$CLUSTER" 2>/dev/null && \
            echo "  loaded ${REGISTRY}/${svc}:${TAG}" || \
            echo "  (skip) ${REGISTRY}/${svc}:${TAG}"
    fi
done

echo ""
echo "Done."
