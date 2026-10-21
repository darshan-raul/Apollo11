#!/bin/bash
# Static validation for the GitOps module. No cluster or network required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="$(dirname "$SCRIPT_DIR")"
STAGE_DIR="$(dirname "$ARGOCD_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"

for env in dev staging prod; do
    app_file="$ARGOCD_DIR/applications/$env.yaml"
    apps_ns="apollo-airlines-$env-apps"
    ui_ns="apollo-airlines-$env-ui"
    grep -q 'namespace: argocd' "$app_file"
    grep -q 'repoURL: https://github.com/darshan-raul/Apollo11.git' "$app_file"
    grep -q "namespace: $apps_ns" "$app_file"
    grep -q "value: $ui_ns" "$app_file"

    render=$(mktemp)
    helm template "apollo11-$env" "$CHART_DIR" \
        -f "$CHART_DIR/values-$env.yaml" \
        --set image.repository=ghcr.io/darshan-raul/apollo11/stage6 \
        --set namespaces.apps="$apps_ns" \
        --set namespaces.ui="$ui_ns" \
        --set gateway.createClass=false \
        --set gateway.envoy.bundleInstall=false \
        --set metallb.enabled=false \
        --set observability.enabled=false > "$render"

    if grep -Eq '^kind: (Namespace|GatewayClass|IPAddressPool|L2Advertisement)$' "$render"; then
        echo "ERROR: $env Application render contains platform-owned resources" >&2
        rm -f "$render"
        exit 1
    fi
    if grep -E '^  namespace:' "$render" | awk '{print $2}' | grep -Ev "^(${apps_ns}|${ui_ns})$" >/dev/null; then
        echo "ERROR: $env Application renders outside its namespace pair" >&2
        rm -f "$render"
        exit 1
    fi
    count=$(grep -c '^kind:' "$render")
    expected=60
    [[ "$env" == "prod" ]] && expected=62
    if [[ "$count" -ne "$expected" ]]; then
        echo "ERROR: $env rendered $count resources; expected $expected" >&2
        rm -f "$render"
        exit 1
    fi
    rm -f "$render"
    echo "$env: $count isolated tenant resources"
done

obs_render=$(mktemp)
kubectl kustomize "$ARGOCD_DIR/platform/observability" > "$obs_render"
if grep -E '^  namespace:' "$obs_render" | awk '{print $2}' | grep -Ev '^apollo-observability$' >/dev/null; then
    echo "ERROR: shared observability Application renders outside apollo-observability" >&2
    rm -f "$obs_render"
    exit 1
fi
obs_count=$(grep -c '^kind:' "$obs_render")
[[ "$obs_count" -eq 44 ]] || { echo "ERROR: observability rendered $obs_count resources; expected 44" >&2; rm -f "$obs_render"; exit 1; }
rm -f "$obs_render"
echo "observability: $obs_count shared namespaced resources"

echo "Argo CD static validation passed."
