#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="${STAGE_DIR}/k8s"

ACTION=""
FAULT_ID=""
CONTEXT="${KUBE_CONTEXT:-}"
CLUSTER=""

FAULT_IDS=(
  "bad-readiness-path"
  "bad-liveness-path"
  "missing-redis-url"
  "taint-block"
  "oom-limit"
)

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  --list               List available fault drill IDs (safe offline, no cluster mutations)
  --inject             Inject a random Stage 4 fault and print spoiler-free symptom clues
  --inject-id <name>   Inject a specific fault ID deterministically
  --verify             Verify Stage 4 cluster recovery after remediation
  --restore            Restore clean Stage 4 manifests, taints, and rollouts

Options:
  --context <ctx>      Target kubectl context (kind-apollo11 or kind-apollo11-dev)
  --cluster <name>     Cluster base name (default: apollo11)
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --list)
      ACTION="list"
      shift
      ;;
    --inject)
      ACTION="inject"
      shift
      ;;
    --inject-id)
      [[ $# -ge 2 ]] || { echo "--inject-id requires a fault name" >&2; exit 2; }
      ACTION="inject-id"
      FAULT_ID="$2"
      shift 2
      ;;
    --verify)
      ACTION="verify"
      shift
      ;;
    --restore)
      ACTION="restore"
      shift
      ;;
    --context)
      [[ $# -ge 2 ]] || { echo "--context requires a value" >&2; exit 2; }
      CONTEXT="$2"
      shift 2
      ;;
    --cluster)
      [[ $# -ge 2 ]] || { echo "--cluster requires a value" >&2; exit 2; }
      CLUSTER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  usage >&2
  exit 2
fi

if [[ "$ACTION" == "list" ]]; then
  echo "Available Stage 4 fault drills:"
  for id in "${FAULT_IDS[@]}"; do
    echo "  - ${id}"
  done
  exit 0
fi

CONTEXT="${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
CLUSTER="${CLUSTER:-apollo11}"
ALLOWED_CONTEXTS=("kind-${CLUSTER}" "kind-${CLUSTER}-dev")

ctx_matched=false
for allowed in "${ALLOWED_CONTEXTS[@]}"; do
  if [[ "$CONTEXT" == "$allowed" ]]; then
    ctx_matched=true
    break
  fi
done

if [[ "$ctx_matched" != "true" ]]; then
  echo "Refusing to run against context '${CONTEXT:-<none>}'." >&2
  echo "This script only targets one of: ${ALLOWED_CONTEXTS[*]}" >&2
  exit 2
fi

kube() {
  kubectl --context "$CONTEXT" "$@"
}

print_ladder_instructions() {
  local symptom="$1"
  cat <<EOF

=== Stage 4 Blind Troubleshooting Drill ===
Context: ${CONTEXT}

Observable Symptom:
  ${symptom}

Investigate using the Ignition 5-Rung Evidence Ladder (stop once root cause is proven):
  1. Status   : kubectl --context ${CONTEXT} get pods,deploy,svc,endpointslices -n apollo-airlines-apps -o wide
  2. Events   : kubectl --context ${CONTEXT} get events -n apollo-airlines-apps --sort-by=.metadata.creationTimestamp | tail -25
  3. Detail   : kubectl --context ${CONTEXT} describe <resource>/<name> -n apollo-airlines-apps
  4. Logs     : kubectl --context ${CONTEXT} logs <pod> -n apollo-airlines-apps [--previous]
  5. Behavior : Query Envoy Gateway (http://<GATEWAY_IP>/healthz with Host header) or check EndpointSlices

Record your findings using: learner-work/EVIDENCE_TEMPLATE.md
  Copy to: learner-work/stage4/work/fault-drill.md

When you have fixed the cluster, verify recovery with:
  ./stages/stage4/scripts/fault-drill.sh --verify --context ${CONTEXT}

To discard and reset to clean Stage 4 manifests at any time:
  ./stages/stage4/scripts/fault-drill.sh --restore --context ${CONTEXT}
EOF
}

inject_fault() {
  local id="$1"
  local symptom=""

  case "$id" in
    bad-readiness-path)
      kube patch deployment booking -n apollo-airlines-apps --type=strategic -p '{
        "spec": {
          "strategy": {"rollingUpdate": {"maxUnavailable": 2}},
          "template": {
            "spec": {
              "containers": [{
                "name": "booking",
                "readinessProbe": {
                  "httpGet": {"path": "/healthz/nonexistent"},
                  "initialDelaySeconds": 2,
                  "periodSeconds": 3,
                  "failureThreshold": 1
                }
              }]
            }
          }
        }
      }' >/dev/null
      for _ in $(seq 1 20); do
        local ready
        ready="$(kube get deployment booking -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
        if [[ "${ready:-0}" -eq 0 ]]; then
          break
        fi
        sleep 2
      done
      symptom="Requests to booking.apollo.local/healthz via Envoy Gateway are failing (HTTP 503), even though booking Pods appear Running."
      ;;
    bad-liveness-path)
      kube patch deployment flight -n apollo-airlines-apps --type=strategic -p '{
        "spec": {
          "strategy": {"rollingUpdate": {"maxUnavailable": 2}},
          "template": {
            "spec": {
              "containers": [{
                "name": "flight",
                "livenessProbe": {
                  "httpGet": {"path": "/healthz/dead"},
                  "initialDelaySeconds": 2,
                  "periodSeconds": 2,
                  "failureThreshold": 2
                }
              }]
            }
          }
        }
      }' >/dev/null
      for _ in $(seq 1 25); do
        local restarts
        restarts="$(kube get pods -n apollo-airlines-apps -l app=flight -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")"
        if [[ "${restarts:-0}" -ge 1 ]]; then
          break
        fi
        sleep 2
      done
      symptom="The flight service in apollo-airlines-apps is unstable: pods are restarting repeatedly and flight.apollo.local requests fail."
      ;;
    missing-redis-url)
      kube patch deployment notification -n apollo-airlines-apps --type=strategic -p '{
        "spec": {
          "strategy": {"rollingUpdate": {"maxUnavailable": 2}},
          "template": {
            "spec": {
              "containers": [{
                "name": "notification",
                "env": [{"name": "REDIS_URL", "value": "redis://missing-redis:6379"}],
                "readinessProbe": {
                  "initialDelaySeconds": 2,
                  "periodSeconds": 3,
                  "failureThreshold": 1
                }
              }]
            }
          }
        }
      }' >/dev/null
      for _ in $(seq 1 20); do
        local ready
        ready="$(kube get deployment notification -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
        if [[ "${ready:-0}" -eq 0 ]]; then
          break
        fi
        sleep 2
      done
      symptom="notification.apollo.local/healthz is returning HTTP 503 and notification Pods remain Running without becoming Ready."
      ;;
    taint-block)
      local workers
      workers="$(kube get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
      if [[ -z "$workers" ]]; then
        echo "No non-control-plane worker nodes found." >&2
        exit 1
      fi
      for node in $workers; do
        kube taint node "$node" apollo11.io/drill=blocked:NoSchedule --overwrite >/dev/null
      done
      kube delete pod -n apollo-airlines-apps -l app=search --wait=false >/dev/null 2>&1 || true
      for _ in $(seq 1 15); do
        local phase
        phase="$(kube get pods -n apollo-airlines-apps -l app=search -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
        if [[ "$phase" == "Pending" ]]; then
          break
        fi
        sleep 2
      done
      symptom="search.apollo.local/healthz is failing (HTTP 503) and replacement search Pods are stuck without running."
      ;;
    oom-limit)
      kube patch deployment identity -n apollo-airlines-apps --type=strategic -p '{
        "spec": {
          "strategy": {"rollingUpdate": {"maxUnavailable": 2}},
          "template": {
            "spec": {
              "containers": [{
                "name": "identity",
                "resources": {
                  "requests": {"memory": "16Mi"},
                  "limits": {"memory": "16Mi"}
                }
              }]
            }
          }
        }
      }' >/dev/null
      for _ in $(seq 1 20); do
        local ready
        ready="$(kube get deployment identity -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
        if [[ "${ready:-0}" -eq 0 ]]; then
          break
        fi
        sleep 2
      done
      symptom="identity.apollo.local/healthz is returning HTTP 503 and identity Pods fail to stay running."
      ;;
    *)
      echo "Unknown fault ID: $id" >&2
      exit 2
      ;;
  esac

  print_ladder_instructions "$symptom"
}

restore_clean() {
  echo "=== Restoring clean Stage 4 state on ${CONTEXT} ==="
  local all_nodes
  all_nodes="$(kube get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  for node in $all_nodes; do
    kube taint node "$node" apollo11.io/drill- >/dev/null 2>&1 || true
    kube taint node "$node" apollo11.io/maintenance- >/dev/null 2>&1 || true
  done

  for dep in identity flight booking search notification; do
    if kube get deployment "$dep" -n apollo-airlines-apps >/dev/null 2>&1; then
      kube patch deployment "$dep" -n apollo-airlines-apps --type=strategic \
        -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":"25%"}}}}' >/dev/null 2>&1 || true
    fi
  done

  kube apply -f "${K8S_DIR}/config/"
  for app_dir in identity flight booking search notification frontend; do
    kube apply -f "${K8S_DIR}/apps/${app_dir}/"
  done
  kube apply -f "${K8S_DIR}/pdb/"

  for dep in identity flight booking search notification; do
    kube rollout status "deployment/${dep}" -n apollo-airlines-apps --timeout=120s
  done
  kube rollout status deployment/frontend -n apollo-airlines-ui --timeout=120s
  echo "Stage 4 cluster state restored cleanly."
}

verify_recovery() {
  echo "=== Verifying Stage 4 Fault Recovery on ${CONTEXT} ==="
  local failures=0

  local nodes
  nodes="$(kube get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  for node in $nodes; do
    local taints
    taints="$(kube get node "$node" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null || true)"
    if [[ "$taints" == *"apollo11.io/drill"* || "$taints" == *"apollo11.io/maintenance"* ]]; then
      echo "[FAIL] Node $node still has drill/maintenance taint: $taints" >&2
      failures=$((failures + 1))
    fi
  done

  for entry in "apollo-airlines-apps:identity" "apollo-airlines-apps:flight" "apollo-airlines-apps:booking" "apollo-airlines-apps:search" "apollo-airlines-apps:notification" "apollo-airlines-ui:frontend"; do
    local ns="${entry%%:*}"
    local dep="${entry##*:}"
    local ready
    ready="$(kube get pods -n "$ns" -l "app=$dep" -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && $2=="True"{c++} END{print c+0}')"
    if [[ "${ready:-0}" -ge 2 ]]; then
      echo "[PASS] $ns/$dep has $ready ready non-terminating replicas"
    else
      echo "[FAIL] $ns/$dep has $ready ready replicas (expected >= 2)" >&2
      failures=$((failures + 1))
    fi

    local bad_states
    bad_states="$(kube get pods -n "$ns" -l "app=$dep" -o jsonpath='{range .items[*]}{.status.phase}{" "}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{.lastState.terminated.reason}{" "}{end}{"\n"}{end}' 2>/dev/null || true)"
    if [[ "$bad_states" == *"CrashLoopBackOff"* || "$bad_states" == *"Pending"* ]]; then
      echo "[FAIL] $ns/$dep has unhealthy pod state: $bad_states" >&2
      failures=$((failures + 1))
    fi
  done

  local gateway_ip
  gateway_ip="$(kube get service -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -z "$gateway_ip" ]]; then
    echo "[FAIL] Envoy Gateway LoadBalancer IP not found" >&2
    failures=$((failures + 1))
  else
    for host in identity.apollo.local flight.apollo.local booking.apollo.local search.apollo.local notification.apollo.local; do
      local code
      code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -H "Host: $host" "http://${gateway_ip}/healthz" 2>/dev/null || echo "000")"
      if [[ "$code" == "200" ]]; then
        echo "[PASS] Gateway HTTP /healthz for $host returned 200"
      else
        echo "[FAIL] Gateway HTTP /healthz for $host returned $code" >&2
        failures=$((failures + 1))
      fi
    done
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "Recovery verification FAILED with $failures error(s)." >&2
    exit 1
  fi
  echo "Recovery verification PASSED: all Stage 4 services are healthy."
}

case "$ACTION" in
  inject)
    idx=$((RANDOM % ${#FAULT_IDS[@]}))
    inject_fault "${FAULT_IDS[$idx]}"
    ;;
  inject-id)
    valid=false
    for fid in "${FAULT_IDS[@]}"; do
      if [[ "$fid" == "$FAULT_ID" ]]; then
        valid=true
        break
      fi
    done
    if [[ "$valid" != "true" ]]; then
      echo "Unknown fault ID: '$FAULT_ID'. Run '$0 --list' to see valid IDs." >&2
      exit 2
    fi
    inject_fault "$FAULT_ID"
    ;;
  verify)
    verify_recovery
    ;;
  restore)
    restore_clean
    ;;
esac
