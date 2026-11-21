#!/bin/bash
# Build all 6 Apollo Airlines application images (5 backends + frontend).
#
# Default tag is `latest` (matches the Helm chart default and the kustomize
# base). The frontend image is rebuilt with the VITE_* URLs from the chart's
# values.yaml so the rendered SPA and the HTTPRoute hostnames never drift.
#
#   ./scripts/build-images.sh                # build all 6, load to kind
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
    local code="${1:-1}"
    cat <<EOF
Usage: $0 [--tag TAG] [--cluster NAME] [--skip-load]

Options:
  --tag TAG         Image tag to apply to all 6 services (default: latest)
  --cluster NAME    kind cluster name to load images into (default: apollo11)
  --skip-load       Build only; skip loading images into kind
  --help            Show this help
EOF
    exit "$code"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)        [[ $# -ge 2 ]] || { echo "--tag requires a value" >&2; usage 2; }; TAG="$2"; shift 2 ;;
        --cluster)    [[ $# -ge 2 ]] || { echo "--cluster requires a value" >&2; usage 2; }; CLUSTER="$2"; shift 2 ;;
        --skip-load)  SKIP_KIND_LOAD=true; shift ;;
        --help|-h)    usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

SERVICES="identity flight booking search notification"
ALL_SERVICES="identity flight booking search notification frontend"

# Extract VITE_* URLs from the Helm chart's values.yaml so the frontend
# image and the HTTPRoutes never drift.
extract_vite_url() {
    local key="$1"
    awk -v k="$key" '
        /^  viteUrls:/ { in_vite=1; next }
        in_vite && $1 == k ":" {
            value=$2
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
        in_vite && /^[^ ]/ { exit }
    ' "$CHART_DIR/values.yaml"
}

VITE_IDENTITY_URL=$(extract_vite_url identity)
VITE_FLIGHT_URL=$(extract_vite_url flight)
VITE_BOOKING_URL=$(extract_vite_url booking)
VITE_SEARCH_URL=$(extract_vite_url search)

for value_name in VITE_IDENTITY_URL VITE_FLIGHT_URL VITE_BOOKING_URL VITE_SEARCH_URL; do
    if [[ -z "${!value_name}" ]]; then
        echo "ERROR: could not read $value_name from $CHART_DIR/values.yaml" >&2
        exit 1
    fi
done

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
        echo "ERROR: required service directory not found: $CODE_DIR/$svc" >&2
        exit 1
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
else
    echo "ERROR: required frontend directory not found: $CODE_DIR/frontend" >&2
    exit 1
fi

if [[ "$SKIP_KIND_LOAD" == "true" ]]; then
    echo ""
    echo "Skipped loading into kind (--skip-load)."
    exit 0
fi

# Load into kind
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
    echo ""
    echo "kind cluster '${CLUSTER}' not found." >&2
    echo "Run: kind create cluster --name ${CLUSTER}" >&2
    exit 1
fi

echo ""
echo "=== Loading images into kind cluster '$CLUSTER' ==="
for svc in $ALL_SERVICES; do
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${REGISTRY}/${svc}:${TAG}$"; then
        echo "ERROR: image was not built: ${REGISTRY}/${svc}:${TAG}" >&2
        exit 1
    fi
    kind load docker-image "${REGISTRY}/${svc}:${TAG}" --name "$CLUSTER" >/dev/null
    echo "  loaded ${REGISTRY}/${svc}:${TAG}"
done

echo ""
echo "Done."
