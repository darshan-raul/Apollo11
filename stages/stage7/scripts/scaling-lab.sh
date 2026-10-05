#!/bin/bash
# Observable Stage 7 scheduling + HPA exercise.
#
# The default `run` path is reversible:
#   1. label + taint one worker as a preferred search pool;
#   2. recreate search Pods so the scheduler evaluates the policy;
#   3. temporarily lower the HPA CPU target and scale-down window;
#   4. generate real HTTP traffic from short-lived in-cluster clients;
#   5. prove scale-out, cross-worker placement, and scale-in;
#   6. restore the HPA and remove all lab-created cluster state.
#
# Usage:
#   bash scripts/scaling-lab.sh
#   bash scripts/scaling-lab.sh run
#   bash scripts/scaling-lab.sh cleanup
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/context.sh"
apollo_context_guard

NAMESPACE="apollo-airlines-apps"
SEARCH_DEPLOYMENT="search"
HPA_NAME="search-hpa"
LOAD_DEPLOYMENT="search-load"
POOL_LABEL="apollo11.io/search-pool"
POOL_VALUE="dedicated"
TAINT_KEY="workload"
TAINT_VALUE="search"
TAINT_EFFECT="NoSchedule"
LAB_CPU_TARGET=10
LAB_SCALE_DOWN_WINDOW=30
SCALE_OUT_TIMEOUT=240
SCALE_IN_TIMEOUT=300
ACTION="${1:-run}"

ORIGINAL_CPU_TARGET=""
ORIGINAL_SCALE_DOWN_WINDOW=""
DEDICATED_NODE=""
CLEANED_UP=false

log() { printf '\n==> %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

worker_nodes() {
    kubectl get nodes -l node-role=worker \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
}

remove_lab_node_state() {
    local node
    while IFS= read -r node; do
        [[ -n "$node" ]] || continue
        kubectl taint node "$node" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}-" >/dev/null 2>&1 || true
        kubectl label node "$node" "${POOL_LABEL}-" >/dev/null 2>&1 || true
    done < <(worker_nodes)
}

restore_hpa() {
    if [[ -n "$ORIGINAL_CPU_TARGET" && -n "$ORIGINAL_SCALE_DOWN_WINDOW" ]] && \
       kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        if ! kubectl patch hpa "$HPA_NAME" -n "$NAMESPACE" --type merge \
            -p "{\"spec\":{\"metrics\":[{\"type\":\"Resource\",\"resource\":{\"name\":\"cpu\",\"target\":{\"type\":\"Utilization\",\"averageUtilization\":${ORIGINAL_CPU_TARGET}}}}],\"behavior\":{\"scaleDown\":{\"stabilizationWindowSeconds\":${ORIGINAL_SCALE_DOWN_WINDOW},\"policies\":[{\"type\":\"Percent\",\"value\":50,\"periodSeconds\":60}]}}}}" \
            >/dev/null; then
            return 1
        fi
        kubectl annotate hpa "$HPA_NAME" -n "$NAMESPACE" \
            apollo11.io/scaling-lab-original-cpu- \
            apollo11.io/scaling-lab-original-window- \
            >/dev/null 2>&1 || true
    fi
}

cleanup() {
    local hpa_restored=true
    [[ "$CLEANED_UP" == "false" ]] || return
    CLEANED_UP=true
    log "Cleaning up the load generator and restoring cluster settings"
    kubectl delete deployment "$LOAD_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if ! restore_hpa; then
        hpa_restored=false
        printf 'WARNING: could not restore the HPA; rerun with the cleanup action.\n' >&2
    fi
    remove_lab_node_state
    if [[ "$hpa_restored" == "true" ]]; then
        printf 'Lab state removed. The chart-defined HPA policy is restored.\n'
    else
        printf 'Load generator and node metadata removed; HPA restoration still needs attention.\n' >&2
    fi
}

on_signal() {
    cleanup
    exit 130
}

wait_for_replica_count() {
    local comparison="$1" expected="$2" timeout_seconds="$3"
    local elapsed=0 current=0
    while (( elapsed < timeout_seconds )); do
        current=$(kubectl get deployment "$SEARCH_DEPLOYMENT" -n "$NAMESPACE" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
        current=${current:-0}
        printf '  %3ss  ready replicas=%s  ' "$elapsed" "$current"
        kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null || true
        if [[ "$comparison" == "gt" && "$current" -gt "$expected" ]]; then return 0; fi
        if [[ "$comparison" == "eq" && "$current" -eq "$expected" ]]; then return 0; fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    return 1
}

if [[ "$ACTION" == "cleanup" ]]; then
    ORIGINAL_CPU_TARGET=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" \
        -o go-template='{{index .metadata.annotations "apollo11.io/scaling-lab-original-cpu"}}' 2>/dev/null || true)
    ORIGINAL_SCALE_DOWN_WINDOW=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" \
        -o go-template='{{index .metadata.annotations "apollo11.io/scaling-lab-original-window"}}' 2>/dev/null || true)
    if ! restore_hpa; then
        printf 'WARNING: could not restore the recorded HPA settings.\n' >&2
    fi
    remove_lab_node_state
    kubectl delete deployment "$LOAD_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
    printf 'Removed Stage 7 scaling-lab state and restored its recorded HPA settings.\n'
    exit 0
fi
[[ "$ACTION" == "run" ]] || die "unknown action '$ACTION' (expected run or cleanup)"

for resource in "deployment/$SEARCH_DEPLOYMENT" "hpa/$HPA_NAME"; do
    kubectl get "$resource" -n "$NAMESPACE" >/dev/null 2>&1 || \
        die "$resource is missing; deploy Stage 7 first"
done
kubectl top nodes >/dev/null 2>&1 || die "metrics-server is not returning data yet"

mapfile -t WORKERS < <(worker_nodes)
[[ "${#WORKERS[@]}" -ge 2 ]] || die "this lab requires at least two nodes labeled node-role=worker"
DEDICATED_NODE="${WORKERS[0]}"

ORIGINAL_CPU_TARGET=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')
ORIGINAL_SCALE_DOWN_WINDOW=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}')
MIN_REPLICAS=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
SEARCH_IMAGE=$(kubectl get deployment "$SEARCH_DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')

trap cleanup EXIT
trap on_signal INT TERM

log "Designating $DEDICATED_NODE as the preferred search worker"
remove_lab_node_state
kubectl label node "$DEDICATED_NODE" "${POOL_LABEL}=${POOL_VALUE}" --overwrite
kubectl taint node "$DEDICATED_NODE" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}" --overwrite
kubectl delete pod -n "$NAMESPACE" -l app=search --wait=false >/dev/null
kubectl rollout status deployment "$SEARCH_DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
kubectl get pods -n "$NAMESPACE" -l app=search -o wide

log "Temporarily tuning the HPA for a short local demonstration"
printf 'Production values: CPU target=%s%%, scale-down window=%ss\n' \
    "$ORIGINAL_CPU_TARGET" "$ORIGINAL_SCALE_DOWN_WINDOW"
printf 'Lab values:        CPU target=%s%%, scale-down window=%ss\n' \
    "$LAB_CPU_TARGET" "$LAB_SCALE_DOWN_WINDOW"
kubectl annotate hpa "$HPA_NAME" -n "$NAMESPACE" --overwrite \
    "apollo11.io/scaling-lab-original-cpu=${ORIGINAL_CPU_TARGET}" \
    "apollo11.io/scaling-lab-original-window=${ORIGINAL_SCALE_DOWN_WINDOW}" \
    >/dev/null
kubectl patch hpa "$HPA_NAME" -n "$NAMESPACE" --type merge \
    -p "{\"spec\":{\"metrics\":[{\"type\":\"Resource\",\"resource\":{\"name\":\"cpu\",\"target\":{\"type\":\"Utilization\",\"averageUtilization\":${LAB_CPU_TARGET}}}}],\"behavior\":{\"scaleDown\":{\"stabilizationWindowSeconds\":${LAB_SCALE_DOWN_WINDOW},\"policies\":[{\"type\":\"Percent\",\"value\":50,\"periodSeconds\":15}]}}}}" \
    >/dev/null

log "Starting bounded in-cluster HTTP load"
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${LOAD_DEPLOYMENT}
  namespace: ${NAMESPACE}
  labels:
    app: ${LOAD_DEPLOYMENT}
    apollo11.io/temporary: "true"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: ${LOAD_DEPLOYMENT}
  template:
    metadata:
      labels:
        app: ${LOAD_DEPLOYMENT}
        apollo11.io/temporary: "true"
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: load
          image: ${SEARCH_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args:
            - |
              i=0
              while [ \$i -lt 12 ]; do
                while true; do
                  wget -q -O /dev/null 'http://search:8083/api/search?origin=BOM&destination=SIN&date=2026-06-17' || true
                done &
                i=\$((i + 1))
              done
              wait
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {cpu: 250m, memory: 64Mi}
EOF
kubectl rollout status deployment "$LOAD_DEPLOYMENT" -n "$NAMESPACE" --timeout=120s

log "Watching for HPA scale-out"
if ! wait_for_replica_count gt "$MIN_REPLICAS" "$SCALE_OUT_TIMEOUT"; then
    die "search did not scale above minReplicas=$MIN_REPLICAS within ${SCALE_OUT_TIMEOUT}s"
fi

log "Search replicas after scale-out"
kubectl get pods -n "$NAMESPACE" -l app=search -o wide
DISTINCT_NODES=$(kubectl get pods -n "$NAMESPACE" -l app=search \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | sed '/^$/d' | wc -l | tr -d ' ')
[[ "$DISTINCT_NODES" -ge 2 ]] || die "search replicas used only $DISTINCT_NODES worker; expected at least 2"
printf 'Observed search replicas across %s workers.\n' "$DISTINCT_NODES"

log "Stopping load and watching scale-in to minReplicas=$MIN_REPLICAS"
kubectl delete deployment "$LOAD_DEPLOYMENT" -n "$NAMESPACE" --wait=false >/dev/null
if ! wait_for_replica_count eq "$MIN_REPLICAS" "$SCALE_IN_TIMEOUT"; then
    die "search did not return to minReplicas=$MIN_REPLICAS within ${SCALE_IN_TIMEOUT}s"
fi

log "Lab complete"
printf 'Observed real HTTP load, HPA scale-out, cross-worker placement, and scale-in.\n'
