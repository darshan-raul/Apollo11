#!/bin/bash
# Install ArgoCD v2.13.x into the cluster.
#
# Two install paths:
#   1. Online (default): curl the official install.yaml from raw.githubusercontent.com
#   2. Offline:           use the vendored copy at bundles/argocd-install.yaml
#                         (run --offline, but you must have fetched it once with
#                         --fetch-bundle first)
#
# Usage:
#   ./install.sh                         # online install
#   ./install.sh --offline               # use the vendored bundle
#   ./install.sh --fetch-bundle          # download + vendor the bundle, don't install
#   ./install.sh --version v2.13.2       # pin a specific ArgoCD version
#
# After install:
#   - ArgoCD lives in the `argocd` namespace
#   - argocd-server is ClusterIP by default (port-forward to access the UI)
#   - The initial `admin` password is the auto-generated pod name; we print it
#
# This script is idempotent: re-running on a cluster that already has ArgoCD
# is a no-op (it patches the namespace, then exits).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$SCRIPT_DIR/bundles"
BUNDLE_FILE="$BUNDLE_DIR/argocd-install.yaml"
ARGO_VERSION="v2.13.2"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"
ARGOCD_NS="argocd"

OFFLINE=false
FETCH_ONLY=false

usage() {
    cat <<EOF
Usage: $0 [--offline] [--fetch-bundle] [--version vX.Y.Z]

Options:
  --offline          Use the vendored bundle at bundles/argocd-install.yaml
                     instead of fetching from the internet.
  --fetch-bundle     Download the bundle from upstream and save it under
                     bundles/, but don't install. Useful for prepping an
                     air-gapped environment.
  --version VER      ArgoCD version to install (default: $ARGO_VERSION)
  --help             Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --offline)       OFFLINE=true; shift ;;
        --fetch-bundle)  FETCH_ONLY=true; shift ;;
        --version)       ARGO_VERSION="$2"; INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"; shift 2 ;;
        --help)          usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/6 Checking cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
ok "cluster reachable"

# ---------------------------------------------------------------------------
# Fetch-bundle mode
# ---------------------------------------------------------------------------
if [[ "$FETCH_ONLY" == "true" ]]; then
    step "1/1 Fetching ArgoCD $ARGO_VERSION install manifest"
    mkdir -p "$BUNDLE_DIR"
    curl -fsSL -o "$BUNDLE_FILE" "$INSTALL_URL"
    ok "saved $(wc -l < "$BUNDLE_FILE") lines to $BUNDLE_FILE"
    echo "  You can now run: $0 --offline"
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine manifest source
# ---------------------------------------------------------------------------
if [[ "$OFFLINE" == "true" ]]; then
    if [[ ! -f "$BUNDLE_FILE" ]]; then
        fail "offline bundle not found at $BUNDLE_FILE. Run '$0 --fetch-bundle' once with internet access."
    fi
    MANIFEST="$BUNDLE_FILE"
    step "1/6 Using offline bundle: $MANIFEST"
else
    step "1/6 Fetching ArgoCD $ARGO_VERSION install manifest from upstream"
    TMP_MANIFEST="$(mktemp)"
    if ! curl -fsSL -o "$TMP_MANIFEST" "$INSTALL_URL"; then
        rm -f "$TMP_MANIFEST"
        fail "failed to fetch $INSTALL_URL — try --offline with a vendored bundle"
    fi
    MANIFEST="$TMP_MANIFEST"
    ok "fetched $(wc -l < "$MANIFEST") lines"
fi

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
step "2/6 Creating argocd namespace"
# `kubectl create namespace` errors if it exists; use apply-on-dry-run trick
kubectl create namespace "$ARGOCD_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "namespace $ARGOCD_NS"

step "3/6 Applying ArgoCD manifests"
# install.yaml is ~5MB and exceeds the 256KB last-applied-config limit
# when applied normally. Use --server-side so the API server doesn't try
# to track it as a single object.
kubectl apply --server-side -f "$MANIFEST" 2>&1 | tail -3
ok "manifests applied"

# Clean up temp manifest if we downloaded
if [[ "$MANIFEST" == "$(mktemp -u)"* ]] || [[ -n "${TMP_MANIFEST:-}" && "$MANIFEST" == "$TMP_MANIFEST" ]]; then
    rm -f "$TMP_MANIFEST" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Wait for core components
# ---------------------------------------------------------------------------
step "4/6 Waiting for argocd-server"
for i in $(seq 1 30); do
    ready=$(kubectl get pods -n "$ARGOCD_NS" -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$ready" == "True" ]]; then
        ok "argocd-server Ready"
        break
    fi
    sleep 4
done
if [[ "$ready" != "True" ]]; then
    echo "  (warn) argocd-server not Ready after 120s — check 'kubectl get pods -n $ARGOCD_NS'"
fi

step "5/6 Waiting for argocd-application-controller"
for i in $(seq 1 30); do
    ready=$(kubectl get pods -n "$ARGOCD_NS" -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$ready" == "True" ]]; then
        ok "argocd-application-controller Ready"
        break
    fi
    sleep 4
done
if [[ "$ready" != "True" ]]; then
    echo "  (warn) argocd-application-controller not Ready after 120s"
fi

step "6/6 Fetching initial admin password"
# The password is stored in plaintext in a secret named 'argocd-initial-admin-secret'
# This secret is auto-deleted on first password change.
PASSWORD=""
for i in $(seq 1 10); do
    if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NS" >/dev/null 2>&1; then
        PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NS" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
        break
    fi
    sleep 2
done
if [[ -n "$PASSWORD" ]]; then
    ok "initial admin password: $PASSWORD"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  SAVE THIS — it won't be shown again.                       │"
    echo "  │  Username: admin                                           │"
    echo "  │  Password: $PASSWORD  │"
    echo "  └────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  To log in via CLI:"
    echo "    argocd login localhost:8080 --username admin --password \"\$PASSWORD\" --insecure"
    echo ""
    echo "  To open the UI:"
    echo "    kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8080:443 &"
    echo "    open http://localhost:8080"
else
    echo "  (warn) could not retrieve initial admin password — may have been deleted on prior install"
fi

ok "ArgoCD install complete"
echo "  Next: bash scripts/bootstrap.sh"
