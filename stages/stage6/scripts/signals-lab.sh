#!/usr/bin/env bash
# Add observability cumulatively to an installed Stage 6 baseline.
# Usage: signals-lab.sh render|apply 1..6 [helm|kustomize]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
ACTION="${1:-render}"
SUBSTAGE="${2:-1}"
MODE="${3:-helm}"
[[ "$ACTION" == render || "$ACTION" == apply ]] || { echo 'Expected render or apply' >&2; exit 2; }
[[ "$SUBSTAGE" =~ ^[1-6]$ ]] || { echo 'Expected substage 1..6' >&2; exit 2; }
[[ "$MODE" == helm || "$MODE" == kustomize ]] || { echo 'Expected helm or kustomize' >&2; exit 2; }
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
if [[ "$MODE" == helm ]]; then
  helm template apollo11 "$STAGE_DIR/helm/apollo11" -f "$STAGE_DIR/helm/apollo11/values-dev.yaml" \
    --set gateway.envoy.bundleInstall=false --set metallb.bundleInstall=false \
    | python3 "$SCRIPT_DIR/select-signals.py" --substage "$SUBSTAGE" > "$manifest"
else
  kubectl kustomize "$STAGE_DIR/overlays/dev" \
    | python3 "$SCRIPT_DIR/select-signals.py" --substage "$SUBSTAGE" > "$manifest"
fi
if [[ "$ACTION" == render ]]; then
  cat "$manifest"
  exit 0
fi
source "$SCRIPT_DIR/context.sh"
apollo_context_guard
# Progress forward only; remove the stage before going back to a smaller set.
current=$(kubectl get configmap apollo-signal-progress -n apollo-observability -o jsonpath='{.data.substage}' --ignore-not-found)
[[ -z "$current" || "$SUBSTAGE" -ge "$current" ]] || { echo 'Teardown before moving to an earlier signal substage.' >&2; exit 2; }
kubectl create namespace apollo-observability --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply --server-side --force-conflicts -f "$STAGE_DIR/bundles/prometheus-operator-v0.93.0.yaml" >/dev/null
kubectl wait --for=condition=Established crd/prometheuses.monitoring.coreos.com --timeout=90s
kubectl rollout status deployment/prometheus-operator -n apollo-observability --timeout=180s
kubectl apply -f "$manifest"
for _ in $(seq 1 60); do
  kubectl get statefulset/prometheus-apollo -n apollo-observability >/dev/null 2>&1 && break
  sleep 2
done
kubectl rollout status statefulset/prometheus-apollo -n apollo-observability --timeout=240s
if [[ "$SUBSTAGE" -ge 2 ]]; then kubectl rollout status deployment/grafana -n apollo-observability --timeout=240s; fi
if [[ "$SUBSTAGE" -ge 4 ]]; then
  kubectl rollout status deployment/loki -n apollo-observability --timeout=240s
  kubectl rollout status daemonset/alloy -n apollo-observability --timeout=240s
fi
if [[ "$SUBSTAGE" -ge 5 ]]; then
  kubectl rollout status deployment/tempo -n apollo-observability --timeout=240s
  kubectl rollout status daemonset/otel-collector -n apollo-observability --timeout=240s
fi
kubectl create configmap apollo-signal-progress -n apollo-observability --from-literal=substage="$SUBSTAGE" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "Signal substage $SUBSTAGE applied. Follow the inspect/break/recover steps in SIGNALS.md."
