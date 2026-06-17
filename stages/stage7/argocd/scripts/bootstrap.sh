#!/bin/bash
# Bootstrap the ArgoCD GitOps module for Stage 5.
#
# What this does:
#   1. Verifies ArgoCD is installed (run ../install.sh first if not)
#   2. Creates the apollo-airlines namespace (for Applications)
#   3. Registers the AppProject (security boundary)
#   4. Registers the 3 Applications (dev, staging, prod)
#   5. (optional) Triggers an initial sync of dev + staging
#
# Idempotent: re-running does not duplicate or break anything.
#
# Usage:
#   ./scripts/bootstrap.sh                       # project + apps, no auto-sync
#   ./scripts/bootstrap.sh --sync                # also force-sync dev + staging
#   ./scripts/bootstrap.sh --sync --include-prod # also force-sync prod (NOT recommended)
#   ./scripts/bootstrap.sh --repo-url URL        # override source.repoURL on all apps
#
# Prerequisites:
#   - kubectl cluster-info works
#   - ArgoCD is installed in the `argocd` namespace (run ../install.sh)
#   - The apollo-airlines-apps and apollo-airlines-ui namespaces do NOT
#     need to exist yet — the chart creates them and the Applications
#     have CreateNamespace=true.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$ARGOCD_DIR/projects"
APPS_DIR="$ARGOCD_DIR/applications"
TENANT_NS="apollo-airlines"

SYNC=false
INCLUDE_PROD=false
REPO_URL_OVERRIDE=""

usage() {
    cat <<EOF
Usage: $0 [--sync] [--include-prod] [--repo-url URL]

Options:
  --sync            After registering the Applications, force-sync dev
                    and staging immediately. Otherwise they'll auto-sync
                    on the next git change.
  --include-prod    Also force-sync prod. NOT recommended outside demos —
                    prod is meant to be human-gated.
  --repo-url URL    Override source.repoURL on all 3 Applications.
                    Default: https://github.com/darshan/Apollo11
  --help            Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --sync)         SYNC=true; shift ;;
        --include-prod) INCLUDE_PROD=true; shift ;;
        --repo-url)     REPO_URL_OVERRIDE="$2"; shift 2 ;;
        --help)         usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

step "0/6 Checking cluster + ArgoCD"
if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot reach a cluster. Did you 'kind create cluster'?"
fi
if ! kubectl get ns argocd >/dev/null 2>&1; then
    fail "ArgoCD namespace not found. Run '../install.sh' first."
fi
ok "ArgoCD is installed"

step "1/6 Creating tenant namespace $TENANT_NS"
# ArgoCD Applications live in a tenant namespace, not the `argocd` system ns.
kubectl create namespace "$TENANT_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "namespace $TENANT_NS"

step "2/6 Registering AppProject"
# AppProject must be created BEFORE the Applications, because Applications
# reference it via spec.project.
kubectl apply -f "$PROJECTS_DIR/project.yaml" 2>&1 | tail -2
ok "AppProject apollo-airlines"

step "3/6 Registering Applications"
for app_yaml in "$APPS_DIR"/*.yaml; do
    name=$(basename "$app_yaml" .yaml)
    if [[ -n "$REPO_URL_OVERRIDE" ]]; then
        # In-place sed — simpler than templating and fine for a 3-file set
        tmp=$(mktemp)
        sed "s|repoURL: https://github.com/darshan/Apollo11|repoURL: $REPO_URL_OVERRIDE|" "$app_yaml" > "$tmp"
        kubectl apply -f "$tmp" 2>&1 | tail -1
        rm -f "$tmp"
    else
        kubectl apply -f "$app_yaml" 2>&1 | tail -1
    fi
    ok "Application $name"
done

step "4/6 Waiting for ArgoCD to pick up the new Applications"
# ArgoCD's app-controller refreshes every 3s by default. We poll the
# resource tree (status.resources) which only gets populated after
# the first reconciliation.
for app in apollo11-dev apollo11-staging apollo11-prod; do
    for i in $(seq 1 15); do
        # application_controller is the label selector for the controller pod
        # (not the application itself). We just wait for the App CR to have
        # an observedGeneration matching its metadata.generation.
        gen=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.status.generation}' 2>/dev/null || echo "")
        observed=$(kubectl get application "$app" -n "$TENANT_NS" -o jsonpath='{.status.observedGeneration}' 2>/dev/null || echo "")
        if [[ -n "$observed" && "$observed" != "0" && "$gen" == "$observed" ]]; then
            ok "$app reconciled (gen=$gen)"
            break
        fi
        sleep 2
    done
done

if [[ "$SYNC" == "true" ]]; then
    step "5/6 Force-syncing dev + staging"
    if command -v argocd >/dev/null 2>&1; then
        # The CLI is preferred — it shows sync status as it runs.
        argocd app sync apollo11-dev --grpc-web 2>&1 | tail -3 || true
        argocd app sync apollo11-staging --grpc-web 2>&1 | tail -3 || true
        if [[ "$INCLUDE_PROD" == "true" ]]; then
            echo "  (--include-prod: syncing apollo11-prod as well)"
            argocd app sync apollo11-prod --grpc-web 2>&1 | tail -3 || true
        fi
    else
        # Fall back to kubectl: the Application controller respects an
        # annotation. Or you can delete the Application and re-apply with
        # operation init. Simplest: just wait for selfHeal to kick in.
        echo "  argocd CLI not found — apps will auto-sync via selfHeal"
        echo "  To force sync manually, install argocd CLI and run:"
        echo "    argocd app sync apollo11-dev"
    fi
else
    step "5/6 Skipping force-sync (run with --sync to force)"
fi

step "6/6 Summary"
echo ""
echo "  Applications registered in namespace '$TENANT_NS':"
kubectl get applications -n "$TENANT_NS" --no-headers 2>/dev/null | awk '{print "    " $1}'
echo ""
echo "  Next steps:"
echo "    1. Watch:        kubectl get applications -n $TENANT_NS -w"
echo "    2. Open the UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "                     open http://localhost:8080"
echo "    3. Verify:       bash scripts/verify.sh"
echo ""
ok "Bootstrap complete"
