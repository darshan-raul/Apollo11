#!/usr/bin/env bash
# Stage 6 Blind Troubleshooting drill: inject, verify, and restore reversible observability faults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTION=""
FAULT_ID=""

FAULT_IDS=(
  "servicemonitor-namespace-selector"
  "notification-bad-redis-url"
  "prometheusrule-label"
  "otel-collector-endpoint"
)

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  --list               List available fault drill IDs (safe offline, no cluster mutations)
  --inject             Inject a random Stage 6 fault and print spoiler-free symptom clues
  --inject-id <name>   Inject a specific fault ID deterministically
  --verify             Verify behavioral recovery of the Stage 6 observability pipeline
  --restore            Idempotently restore backed-up Stage 6 resources and clear drill state

Options:
  --context <ctx>      Target kubectl context (kind-apollo11 or kind-apollo11-dev)
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
      export KUBE_CONTEXT="$2"
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
  cat <<'EOF'
Available Stage 6 fault drills:
  - servicemonitor-namespace-selector : Backend pods are healthy, but Prometheus misses one scrape target.
  - notification-bad-redis-url        : An app Pod stays Running (0/1 Ready) and fails readiness checks.
  - prometheusrule-label              : Prometheus scrapes targets, but Apollo alerts/SLOs disappear from /api/v1/rules.
  - otel-collector-endpoint           : Metrics and logs work, but new cross-service traces fail to reach Tempo.
EOF
  exit 0
fi

# shellcheck source=stages/stage6/scripts/context.sh
source "$SCRIPT_DIR/context.sh"
apollo_context_guard

STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/apollo11-stage6-fault-drill"
STATE_DIR="${STATE_BASE}/${APOLLO_CONTEXT}"
FAULT_FILE="${STATE_DIR}/fault-id"
BACKUP_FILE="${STATE_DIR}/backup.json"
REDIS_ENV_FILE="${STATE_DIR}/redis-env"

PF_PID=""
cleanup_pf() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    wait "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
}
trap cleanup_pf EXIT

free_local_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

start_port_forward() {
  local ns="$1"
  local svc="$2"
  local remote_port="$3"
  local local_port
  local_port="$(free_local_port)"
  cleanup_pf
  kubectl port-forward -n "$ns" "svc/${svc}" "${local_port}:${remote_port}" >/dev/null 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 20); do
    if ! kill -0 "${PF_PID}" >/dev/null 2>&1; then
      PF_PID=""
      return 1
    fi
    if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(0.3); s.connect(('127.0.0.1', int(sys.argv[1]))); s.close()" "${local_port}" >/dev/null 2>&1; then
      printf '%s\n' "${local_port}"
      return 0
    fi
    sleep 0.25
  done
  cleanup_pf
  return 1
}

save_clean_backup() {
  local ns="$1"
  local kind="$2"
  local name="$3"
  local out_file="$4"
  local raw
  raw="$(kubectl get "$kind" "$name" -n "$ns" -o json)"
  python3 - "$out_file" <<'PY' <<<"$raw"
import json, sys
obj = json.load(sys.stdin)
obj.pop("status", None)
meta = obj.setdefault("metadata", {})
for k in ("resourceVersion", "uid", "creationTimestamp", "generation", "managedFields", "selfLink"):
    meta.pop(k, None)
ann = meta.get("annotations")
if isinstance(ann, dict):
    ann.pop("kubectl.kubernetes.io/last-applied-configuration", None)
    if not ann:
        meta.pop("annotations", None)
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(obj, fh, indent=2)
PY
}

print_ladder_instructions() {
  local symptom="$1"
  local clue_area="$2"
  cat <<EOF

=== Stage 6 Blind Troubleshooting Drill ===
Context: ${APOLLO_CONTEXT}

Observable Symptom:
  ${symptom}

Affected Area Clue:
  ${clue_area}

Investigate using the Ignition 5-Rung Evidence Ladder (stop once root cause is proven):
  1. Status   : kubectl --context ${APOLLO_CONTEXT} get pods,deploy,ds,svc,servicemonitor,prometheusrule -n apollo-observability -o wide
                kubectl --context ${APOLLO_CONTEXT} get pods,deploy,svc,endpointslices -n apollo-airlines-apps -o wide
  2. Events   : kubectl --context ${APOLLO_CONTEXT} get events -n apollo-observability --sort-by=.metadata.creationTimestamp | tail -20
                kubectl --context ${APOLLO_CONTEXT} get events -n apollo-airlines-apps --sort-by=.metadata.creationTimestamp | tail -20
  3. Detail   : kubectl --context ${APOLLO_CONTEXT} describe <resource>/<name> -n <namespace>
  4. Logs     : kubectl --context ${APOLLO_CONTEXT} logs -n <namespace> <pod> [--previous]
  5. Behavior :
     - Prometheus API/UI : kubectl --context ${APOLLO_CONTEXT} port-forward -n apollo-observability svc/prometheus 19090:9090
                           (inspect /api/v1/targets and /api/v1/rules or http://127.0.0.1:19090)
     - Grafana UI        : kubectl --context ${APOLLO_CONTEXT} port-forward -n apollo-observability svc/grafana 13000:3000
                           (login: admin / apollo-admin)
     - Traces & Logs     : bash stages/stage6/scripts/trace-test.sh --context ${APOLLO_CONTEXT}

Record your evidence using learner-work/EVIDENCE_TEMPLATE.md:
  mkdir -p learner-work/stage6/work
  cp learner-work/EVIDENCE_TEMPLATE.md learner-work/stage6/work/fault-drill.md

After remediating the cluster, verify behavioral recovery with:
  bash stages/stage6/scripts/fault-drill.sh --verify --context ${APOLLO_CONTEXT}

To discard the drill and restore backed-up resources at any time:
  bash stages/stage6/scripts/fault-drill.sh --restore --context ${APOLLO_CONTEXT}
EOF
}

inject_fault() {
  local id="$1"
  local symptom=""
  local clue_area=""

  if [[ -f "${FAULT_FILE}" ]]; then
    echo "An active Stage 6 fault drill is already recorded for context '${APOLLO_CONTEXT}'." >&2
    echo "Run 'bash stages/stage6/scripts/fault-drill.sh --restore --context ${APOLLO_CONTEXT}' before injecting another fault." >&2
    exit 1
  fi

  mkdir -p "${STATE_DIR}"
  local tmp_backup
  tmp_backup="$(mktemp)"
  local tmp_redis_env=""

  cleanup_on_err() {
    rm -f "${tmp_backup}"
    if [[ -n "${tmp_redis_env}" ]]; then
      rm -f "${tmp_redis_env}"
    fi
  }

  case "$id" in
    servicemonitor-namespace-selector)
      if ! save_clean_backup "apollo-observability" "servicemonitor" "search" "${tmp_backup}"; then
        cleanup_on_err
        echo "Failed to inspect servicemonitor/search in apollo-observability." >&2
        exit 1
      fi
      kubectl patch servicemonitor search -n apollo-observability --type=json \
        -p '[{"op":"replace","path":"/spec/namespaceSelector","value":{"matchNames":["apollo-observability"]}}]' >/dev/null
      mv "${tmp_backup}" "${BACKUP_FILE}"
      printf '%s\n' "$id" > "${FAULT_FILE}"
      symptom="All backend Pods in apollo-airlines-apps are Running and /metrics responds inside the search Pod, but Prometheus /api/v1/targets shows fewer than five healthy Apollo backend targets."
      clue_area="Check Prometheus target discovery and scrape configuration in apollo-observability alongside backend Services in apollo-airlines-apps."
      ;;
    notification-bad-redis-url)
      if ! save_clean_backup "apollo-airlines-apps" "deployment" "notification" "${tmp_backup}"; then
        cleanup_on_err
        echo "Failed to inspect deployment/notification in apollo-airlines-apps." >&2
        exit 1
      fi
      tmp_redis_env="$(mktemp)"
      local dep_json
      dep_json="$(cat "${tmp_backup}")"
      python3 - "${tmp_redis_env}" <<'PY' <<<"${dep_json}"
import json, sys
dep = json.load(sys.stdin)
containers = dep.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
val = None
for c in containers:
    if c.get("name") == "notification":
        for ev in c.get("env") or []:
            if ev.get("name") == "REDIS_URL":
                val = ev.get("value", "")
                break
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    if val is None:
        fh.write("ABSENT\n")
    else:
        fh.write(f"VALUE={val}\n")
PY
      kubectl set env deployment/notification -n apollo-airlines-apps REDIS_URL=redis://redis-broken:6379 >/dev/null
      for _ in $(seq 1 15); do
        local ready
        ready="$(kubectl get deployment notification -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
        if [[ "${ready:-0}" -eq 0 ]]; then
          break
        fi
        sleep 2
      done
      mv "${tmp_backup}" "${BACKUP_FILE}"
      mv "${tmp_redis_env}" "${REDIS_ENV_FILE}"
      printf '%s\n' "$id" > "${FAULT_FILE}"
      symptom="A backend Deployment in apollo-airlines-apps has Pods Running with 0/1 Ready, readiness probes are failing with HTTP 503, and Prometheus shows a missing/down backend target."
      clue_area="Inspect Pod readiness, EndpointSlices, and container logs in apollo-airlines-apps plus Prometheus targets."
      ;;
    prometheusrule-label)
      if ! save_clean_backup "apollo-observability" "prometheusrule" "apollo-services" "${tmp_backup}"; then
        cleanup_on_err
        echo "Failed to inspect prometheusrule/apollo-services in apollo-observability." >&2
        exit 1
      fi
      kubectl patch prometheusrule apollo-services -n apollo-observability --type=merge \
        -p '{"metadata":{"labels":{"app.kubernetes.io/part-of":"detached"}}}' >/dev/null
      mv "${tmp_backup}" "${BACKUP_FILE}"
      printf '%s\n' "$id" > "${FAULT_FILE}"
      symptom="Prometheus is Ready and scraping all five backend targets, but Apollo alert and SLO recording rules (such as ApolloServiceDown and ApolloBookingErrorBudgetBurn) have disappeared from Prometheus /api/v1/rules."
      clue_area="Compare Prometheus rule-selection criteria against rule resources in apollo-observability."
      ;;
    otel-collector-endpoint)
      if ! save_clean_backup "apollo-observability" "configmap" "otel-collector-config" "${tmp_backup}"; then
        cleanup_on_err
        echo "Failed to inspect configmap/otel-collector-config in apollo-observability." >&2
        exit 1
      fi
      local patched_cm
      patched_cm="$(python3 - <<'PY' <"${tmp_backup}"
import json, sys
cm = json.load(sys.stdin)
data = cm.get("data") or {}
relay = data.get("relay.yaml", "")
if "tempo.apollo-observability.svc.cluster.local:4317" not in relay:
    sys.stderr.write("Expected Tempo :4317 endpoint not found in otel-collector-config\n")
    sys.exit(1)
data["relay.yaml"] = relay.replace(
    "tempo.apollo-observability.svc.cluster.local:4317",
    "tempo.apollo-observability.svc.cluster.local:14317",
)
cm["data"] = data
print(json.dumps(cm))
PY
)"
      kubectl apply -f - >/dev/null <<<"${patched_cm}"
      kubectl rollout restart daemonset/otel-collector -n apollo-observability >/dev/null
      kubectl rollout status daemonset/otel-collector -n apollo-observability --timeout=120s >/dev/null || true
      mv "${tmp_backup}" "${BACKUP_FILE}"
      printf '%s\n' "$id" > "${FAULT_FILE}"
      symptom="Booking API requests return 200/201, Prometheus metrics increment, and JSON logs arrive in Loki, but bash stages/stage6/scripts/trace-test.sh fails because new cross-service traces never reach Tempo."
      clue_area="Inspect the distributed trace pipeline components and logs in apollo-observability."
      ;;
    *)
      cleanup_on_err
      echo "Unknown fault ID: $id" >&2
      exit 2
      ;;
  esac

  print_ladder_instructions "$symptom" "$clue_area"
}

check_prometheus_targets() {
  local pf_port payload
  pf_port="$(start_port_forward "apollo-observability" "prometheus" "9090")" || {
    echo "[FAIL] Could not port-forward svc/prometheus in apollo-observability" >&2
    return 1
  }
  payload=""
  for _ in $(seq 1 15); do
    payload="$(curl -fsS --max-time 5 "http://127.0.0.1:${pf_port}/api/v1/targets" 2>/dev/null || true)"
    if [[ -n "$payload" ]] && python3 - <<'PY' <<<"$payload"
import json, sys
d = json.load(sys.stdin)
if d.get("status") != "success":
    sys.exit(1)
up_jobs = set()
for t in d.get("data", {}).get("activeTargets", []):
    if t.get("health") == "up":
        labels = t.get("labels") or {}
        job = labels.get("job") or labels.get("app") or ""
        for svc in ("identity", "flight", "booking", "search", "notification"):
            if job == svc or labels.get("app") == svc:
                up_jobs.add(svc)
sys.exit(0 if {"identity", "flight", "booking", "search", "notification"}.issubset(up_jobs) else 1)
PY
    then
      cleanup_pf
      echo "[PASS] Prometheus /api/v1/targets has all 5 backend services UP"
      return 0
    fi
    sleep 3
  done
  cleanup_pf
  echo "[FAIL] Prometheus /api/v1/targets does not report all 5 backend services UP (identity, flight, booking, search, notification)" >&2
  return 1
}

check_prometheus_rules() {
  local pf_port payload
  pf_port="$(start_port_forward "apollo-observability" "prometheus" "9090")" || {
    echo "[FAIL] Could not port-forward svc/prometheus in apollo-observability" >&2
    return 1
  }
  payload=""
  for _ in $(seq 1 15); do
    payload="$(curl -fsS --max-time 5 "http://127.0.0.1:${pf_port}/api/v1/rules" 2>/dev/null || true)"
    if [[ -n "$payload" ]] && python3 - <<'PY' <<<"$payload"
import json, sys
d = json.load(sys.stdin)
if d.get("status") != "success":
    sys.exit(1)
names = set()
for grp in d.get("data", {}).get("groups", []):
    for r in grp.get("rules", []):
        if r.get("name"):
            names.add(r["name"])
required = {"ApolloServiceDown", "ApolloBookingErrorBudgetBurn", "apollo:booking_error_ratio:5m"}
sys.exit(0 if required.issubset(names) else 1)
PY
    then
      cleanup_pf
      echo "[PASS] Prometheus /api/v1/rules includes Apollo alerts and SLO recording rules"
      return 0
    fi
    sleep 3
  done
  cleanup_pf
  echo "[FAIL] Prometheus /api/v1/rules is missing ApolloServiceDown / ApolloBookingErrorBudgetBurn / apollo:booking_error_ratio:5m" >&2
  return 1
}

verify_recovery() {
  echo "=== Verifying Stage 6 Observability Recovery on ${APOLLO_CONTEXT} ==="
  local failures=0
  local active_fault=""
  if [[ -f "${FAULT_FILE}" ]]; then
    active_fault="$(tr -d '[:space:]' < "${FAULT_FILE}")"
  fi

  # 1. ServiceMonitor/search namespaceSelector must allow apollo-airlines-apps
  local sm_json
  sm_json="$(kubectl get servicemonitor search -n apollo-observability -o json 2>/dev/null || true)"
  if [[ -n "$sm_json" ]] && python3 - <<'PY' <<<"$sm_json"
import json, sys
sm = json.load(sys.stdin)
ns_sel = sm.get("spec", {}).get("namespaceSelector") or {}
ok = ns_sel.get("any") is True or "apollo-airlines-apps" in (ns_sel.get("matchNames") or [])
sys.exit(0 if ok else 1)
PY
  then
    echo "[PASS] servicemonitor/search selects apollo-airlines-apps"
  else
    echo "[FAIL] servicemonitor/search does not select apollo-airlines-apps" >&2
    failures=$((failures + 1))
  fi

  # 2. deployment/notification readiness + live /healthz/ready HTTP 200
  local desired ready
  desired="$(kubectl get deployment notification -n apollo-airlines-apps -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")"
  ready="$(kubectl get deployment notification -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
  if [[ "${desired:-0}" -ge 1 && "${ready:-0}" -ge "${desired}" ]]; then
    local notif_port code
    notif_port="$(start_port_forward "apollo-airlines-apps" "notification" "8084" || true)"
    if [[ -n "${notif_port}" ]]; then
      code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${notif_port}/healthz/ready" 2>/dev/null || echo "000")"
      cleanup_pf
      if [[ "$code" == "200" ]]; then
        echo "[PASS] deployment/notification ready (${ready}/${desired}) and /healthz/ready returned 200"
      else
        echo "[FAIL] svc/notification /healthz/ready returned HTTP ${code}" >&2
        failures=$((failures + 1))
      fi
    else
      echo "[FAIL] Could not port-forward svc/notification in apollo-airlines-apps" >&2
      failures=$((failures + 1))
    fi
  else
    echo "[FAIL] deployment/notification not ready (${ready:-0}/${desired:-0})" >&2
    failures=$((failures + 1))
  fi

  # 3. PrometheusRule/apollo-services selector label
  local pr_label
  pr_label="$(kubectl get prometheusrule apollo-services -n apollo-observability -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null || true)"
  if [[ "${pr_label}" == "apollo-airlines" ]]; then
    echo "[PASS] prometheusrule/apollo-services carries app.kubernetes.io/part-of=apollo-airlines"
  else
    echo "[FAIL] prometheusrule/apollo-services label app.kubernetes.io/part-of is '${pr_label:-<none>}' (expected 'apollo-airlines')" >&2
    failures=$((failures + 1))
  fi

  # 4. otel-collector-config endpoint & DaemonSet readiness
  local cm_data ds_desired ds_ready
  cm_data="$(kubectl get configmap otel-collector-config -n apollo-observability -o jsonpath='{.data.relay\.yaml}' 2>/dev/null || true)"
  ds_desired="$(kubectl get daemonset otel-collector -n apollo-observability -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")"
  ds_ready="$(kubectl get daemonset otel-collector -n apollo-observability -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")"
  if [[ "$cm_data" == *"tempo.apollo-observability.svc.cluster.local:4317"* && "${ds_desired:-0}" -ge 1 && "${ds_ready:-0}" -ge "${ds_desired}" ]]; then
    echo "[PASS] otel-collector-config targets Tempo :4317 and DaemonSet is ready (${ds_ready}/${ds_desired})"
  else
    echo "[FAIL] otel-collector-config or DaemonSet is unhealthy (ready ${ds_ready:-0}/${ds_desired:-0})" >&2
    failures=$((failures + 1))
  fi

  # 5. Behavioral Prometheus targets & rules checks (only poll Prometheus if K8s specs passed or if Prometheus check itself is targeted)
  if [[ "$failures" -eq 0 ]]; then
    if ! check_prometheus_targets; then
      failures=$((failures + 1))
    fi
    if ! check_prometheus_rules; then
      failures=$((failures + 1))
    fi
  fi

  # 6. Behavioral trace delivery check when otel-collector-endpoint was injected or when all static checks pass and no fault file is active
  if [[ "$failures" -eq 0 && ( "$active_fault" == "otel-collector-endpoint" || -z "$active_fault" ) ]]; then
    if bash "$SCRIPT_DIR/trace-test.sh" --context "$APOLLO_CONTEXT"; then
      echo "[PASS] Cross-service trace delivery to Tempo and Loki correlation verified"
    else
      echo "[FAIL] trace-test.sh failed to verify end-to-end trace delivery" >&2
      failures=$((failures + 1))
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "Recovery verification FAILED with ${failures} error(s)." >&2
    exit 1
  fi
  echo "Recovery verification PASSED: Stage 6 observability pipeline is healthy."
}

restore_drill() {
  echo "=== Restoring Stage 6 fault drill state on ${APOLLO_CONTEXT} ==="
  if [[ ! -f "${FAULT_FILE}" ]]; then
    echo "No active Stage 6 fault drill recorded for context '${APOLLO_CONTEXT}'. Nothing to restore."
    return 0
  fi

  local id
  id="$(tr -d '[:space:]' < "${FAULT_FILE}")"

  case "$id" in
    servicemonitor-namespace-selector)
      if [[ -f "${BACKUP_FILE}" ]]; then
        kubectl apply -f "${BACKUP_FILE}" >/dev/null
      else
        kubectl patch servicemonitor search -n apollo-observability --type=json \
          -p '[{"op":"replace","path":"/spec/namespaceSelector","value":{"any":true}}]' >/dev/null
      fi
      ;;
    notification-bad-redis-url)
      if [[ -f "${REDIS_ENV_FILE}" ]]; then
        local env_spec
        env_spec="$(cat "${REDIS_ENV_FILE}")"
        if [[ "${env_spec}" == "ABSENT" ]]; then
          kubectl set env deployment/notification -n apollo-airlines-apps REDIS_URL- >/dev/null
        elif [[ "${env_spec}" == VALUE=* ]]; then
          kubectl set env deployment/notification -n apollo-airlines-apps "REDIS_URL=${env_spec#VALUE=}" >/dev/null
        fi
      else
        kubectl set env deployment/notification -n apollo-airlines-apps REDIS_URL- >/dev/null
      fi
      kubectl rollout status deployment/notification -n apollo-airlines-apps --timeout=120s
      ;;
    prometheusrule-label)
      if [[ -f "${BACKUP_FILE}" ]]; then
        kubectl apply -f "${BACKUP_FILE}" >/dev/null
      else
        kubectl patch prometheusrule apollo-services -n apollo-observability --type=merge \
          -p '{"metadata":{"labels":{"app.kubernetes.io/part-of":"apollo-airlines"}}}' >/dev/null
      fi
      ;;
    otel-collector-endpoint)
      if [[ -f "${BACKUP_FILE}" ]]; then
        kubectl apply -f "${BACKUP_FILE}" >/dev/null
      fi
      kubectl rollout restart daemonset/otel-collector -n apollo-observability >/dev/null
      kubectl rollout status daemonset/otel-collector -n apollo-observability --timeout=120s
      ;;
    *)
      if [[ -f "${BACKUP_FILE}" ]]; then
        kubectl apply -f "${BACKUP_FILE}" >/dev/null
      fi
      ;;
  esac

  rm -f "${FAULT_FILE}" "${BACKUP_FILE}" "${REDIS_ENV_FILE}"
  rmdir "${STATE_DIR}" 2>/dev/null || true
  echo "Stage 6 fault drill state restored cleanly."
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
    restore_drill
    ;;
esac
