#!/usr/bin/env bash
# Stage 2 Blind Troubleshooting Fault Drill (Break-Fix Capstone)
# Injects a Stage 2 Substage 5 networking/Gateway failure without revealing root cause.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONTEXT="${KUBE_CONTEXT:-}"
CONTEXT_SET=false
ACTION=""
INJECT_ID=""

FAULTS=(
  "wrong-selector"
  "bad-route-port"
  "missing-tls-secret"
  "missing-refgrant"
)

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [kind-apollo11|kind-apollo11-dev]

Stage 2 Blind Troubleshooting Drill (requires Substage 5 Envoy Gateway deployed).

Actions (choose one):
  --list               List available fault drill IDs (no cluster mutation)
  --inject             Inject a random Stage 2 fault and print observable clues only
  --inject-id <name>   Inject a specific fault ID deterministically
  --verify             Verify recovery against the live cluster
  --restore            Cleanly restore Stage 2 cluster state from backup/manifests

Options:
  --context <ctx>      Kubernetes context (kind-apollo11 or kind-apollo11-dev)
  --help, -h           Show this help message
EOF
}

list_faults() {
  cat <<'EOF'
Available Stage 2 fault drills:
  wrong-selector      Backend HTTP 503/500 while Pods remain Running
  bad-route-port      Frontend HTTP 500 while backend APIs remain healthy
  missing-tls-secret  HTTPS TLS handshake failure while plain HTTP still responds
  missing-refgrant    Cross-namespace hostname HTTP 500 while primary frontend works
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      ACTION="list"
      shift
      ;;
    --inject)
      ACTION="inject"
      shift
      ;;
    --inject-id)
      [[ $# -ge 2 ]] || { printf 'Missing value for --inject-id\n' >&2; usage >&2; exit 2; }
      ACTION="inject-id"
      INJECT_ID="$2"
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
      [[ $# -ge 2 ]] || { printf 'Missing value for --context\n' >&2; usage >&2; exit 2; }
      CONTEXT="$2"
      CONTEXT_SET=true
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "${CONTEXT_SET}" == false ]]; then
        CONTEXT="$1"
        CONTEXT_SET=true
        shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "${ACTION}" ]]; then
  usage >&2
  exit 2
fi

if [[ "${ACTION}" == "list" ]]; then
  list_faults
  exit 0
fi

if [[ "${CONTEXT_SET}" == false && -z "${CONTEXT}" ]]; then
  CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *)
    printf 'Refusing context %s; Stage 2 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2
    exit 2
    ;;
esac

STATE_FILE="/tmp/.apollo11-stage2-fault-drill-${CONTEXT}.state"
BACKUP_DIR="/tmp/.apollo11-stage2-fault-drill-${CONTEXT}.backup"

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

gateway_ip() {
  kube get svc -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}

require_stage2_substage5() {
  if ! kube get gateway apollo-gateway -n apollo-airlines-apps >/dev/null 2>&1; then
    printf 'Stage 2 Substage 5 (apollo-gateway in apollo-airlines-apps) is not deployed in %s.\n' "${CONTEXT}" >&2
    printf 'Run: bash stages/stage2/scripts/apply.sh --substage 5 --context %s\n' "${CONTEXT}" >&2
    exit 1
  fi
}

print_ladder_instructions() {
  local symptom="$1"
  local probe_cmd="$2"
  cat <<EOF

=== Stage 2 Blind Troubleshooting Drill ===

Symptom Observed:
  ${symptom}

Reproduce / Observe:
  ${probe_cmd}

Investigation Protocol (Ignition 5-Rung Evidence Ladder — see stages/ignition/README.md):
  1. Status   : kubectl --context ${CONTEXT} get pods,deploy,svc,endpointslices,gateway,httproute -A
  2. Events   : kubectl --context ${CONTEXT} get events -n apollo-airlines-apps --sort-by=.metadata.creationTimestamp | tail -20
                kubectl --context ${CONTEXT} get events -n apollo-airlines-ui --sort-by=.metadata.creationTimestamp | tail -20
  3. Detail   : kubectl --context ${CONTEXT} describe <resource>/<name> -n <namespace>
  4. Logs     : kubectl --context ${CONTEXT} logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --tail=50
  5. Behavior : Re-run the failing HTTP/HTTPS check after your fix to prove behavioral recovery.

Record Your Evidence:
  Copy learner-work/EVIDENCE_TEMPLATE.md to learner-work/stage2-drill.md (or /tmp) and
  document: Symptom -> Command Output -> Root Cause -> Fix & Recovery Proof -> Takeaway.

When you believe the cluster is fixed, run:
  bash stages/stage2/scripts/fault-drill.sh --verify --context ${CONTEXT}

To abort and cleanly restore the original state at any time, run:
  bash stages/stage2/scripts/fault-drill.sh --restore --context ${CONTEXT}
EOF
}

backup_tls_secret() {
  umask 077
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  if kube get secret apollo-tls-secret -n apollo-airlines-apps >/dev/null 2>&1; then
    kube get secret apollo-tls-secret -n apollo-airlines-apps -o json | python3 -c '
import json, sys
obj = json.load(sys.stdin)
meta = obj.get("metadata", {})
for k in ("resourceVersion", "uid", "creationTimestamp", "managedFields", "selfLink"):
    meta.pop(k, None)
anns = meta.get("annotations") or {}
anns.pop("kubectl.kubernetes.io/last-applied-configuration", None)
if not anns:
    meta.pop("annotations", None)
json.dump(obj, sys.stdout)
' > "${BACKUP_DIR}/apollo-tls-secret.json"
  fi
}

inject_fault() {
  local fault_id="$1"
  require_stage2_substage5

  if [[ -f "${STATE_FILE}" ]]; then
    printf 'A Stage 2 fault drill is already active in context %s.\n' "${CONTEXT}" >&2
    printf 'Run --verify (after fixing) or --restore before injecting another fault.\n' >&2
    exit 1
  fi

  local eg_ip
  eg_ip="$(gateway_ip)"
  local eg_hint="${eg_ip:-<ENVOY_GATEWAY_IP>}"

  umask 077
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"

  case "${fault_id}" in
    wrong-selector)
      kube patch svc identity -n apollo-airlines-apps --type=merge \
        -p '{"spec":{"selector":{"app":"identity-drift"}}}' >/dev/null
      printf '%s\n' "${fault_id}" > "${STATE_FILE}"
      print_ladder_instructions \
        "Requests to identity.apollo.local/healthz fail (HTTP 503/500) and user login fails, even though application Pods still report Running." \
        "EG_IP=\$(kubectl --context ${CONTEXT} get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}') && curl -i -H 'Host: identity.apollo.local' \"http://\${EG_IP}/healthz\""
      ;;
    bad-route-port)
      kube patch httproute frontend -n apollo-airlines-ui --type=json \
        -p '[{"op":"replace","path":"/spec/rules/0/backendRefs/0/port","value":9999}]' >/dev/null
      printf '%s\n' "${fault_id}" > "${STATE_FILE}"
      print_ladder_instructions \
        "Requests to http://${eg_hint}/ with Host: frontend.apollo.local return HTTP 500, while backend APIs (identity.apollo.local/healthz) still return HTTP 200." \
        "EG_IP=\$(kubectl --context ${CONTEXT} get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}') && curl -i -H 'Host: frontend.apollo.local' \"http://\${EG_IP}/\""
      ;;
    missing-tls-secret)
      backup_tls_secret
      kube delete secret apollo-tls-secret -n apollo-airlines-apps --ignore-not-found >/dev/null
      printf '%s\n' "${fault_id}" > "${STATE_FILE}"
      print_ladder_instructions \
        "HTTPS connections to https://identity.apollo.local/healthz fail during TLS handshake, while plain HTTP (http://${eg_hint}/healthz with Host: identity.apollo.local) still returns HTTP 200." \
        "EG_IP=\$(kubectl --context ${CONTEXT} get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}') && curl -v --resolve \"identity.apollo.local:443:\${EG_IP}\" \"https://identity.apollo.local/healthz\""
      ;;
    missing-refgrant)
      kube delete referencegrant apollo-gateway-grant -n apollo-airlines-ui --ignore-not-found >/dev/null
      printf '%s\n' "${fault_id}" > "${STATE_FILE}"
      print_ladder_instructions \
        "Requests to http://${eg_hint}/ with Host: cross-ns.apollo.local fail with HTTP 500, while Host: frontend.apollo.local still returns HTTP 200." \
        "EG_IP=\$(kubectl --context ${CONTEXT} get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}') && curl -i -H 'Host: cross-ns.apollo.local' \"http://\${EG_IP}/\""
      ;;
    *)
      printf 'Unknown fault ID: %s\n' "${fault_id}" >&2
      list_faults >&2
      exit 2
      ;;
  esac
}

verify_recovery() {
  require_stage2_substage5

  local failures=0
  local eg_ip
  eg_ip="$(gateway_ip)"

  if [[ -z "${eg_ip}" ]]; then
    printf '[FAIL] Envoy Gateway LoadBalancer IP is missing\n' >&2
    return 1
  fi

  # 1. Check identity service endpoints & HTTP route
  local id_ep id_code
  id_ep="$(kube get endpoints identity -n apollo-airlines-apps -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  id_code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: identity.apollo.local' --connect-timeout 3 "http://${eg_ip}/healthz" 2>/dev/null || echo '000')"
  if [[ -n "${id_ep}" && "${id_code}" == "200" ]]; then
    printf '[PASS] identity service endpoints ready and http://identity.apollo.local/healthz returned 200\n'
  else
    printf '[FAIL] identity service endpoints (%s) or HTTP check (%s) unhealthy\n' "${id_ep:-none}" "${id_code}" >&2
    : $((failures+=1))
  fi

  # 2. Check frontend HTTPRoute ResolvedRefs & HTTP 200
  local fe_res fe_code
  fe_res="$(kube get httproute frontend -n apollo-airlines-ui -o jsonpath='{.status.parents[*].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null || true)"
  fe_code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: frontend.apollo.local' --connect-timeout 3 "http://${eg_ip}/" 2>/dev/null || echo '000')"
  if [[ "${fe_res}" == *"True"* && "${fe_res}" != *"False"* && "${fe_code}" == "200" ]]; then
    printf '[PASS] frontend HTTPRoute ResolvedRefs=True and http://frontend.apollo.local/ returned 200\n'
  else
    printf '[FAIL] frontend HTTPRoute ResolvedRefs (%s) or HTTP check (%s) unhealthy\n' "${fe_res:-none}" "${fe_code}" >&2
    : $((failures+=1))
  fi

  # 3. Check TLS Secret, Gateway HTTPS listener ResolvedRefs, and trusted curl
  local tls_exists gw_https_res ca_tmp https_code
  tls_exists="$(kube get secret apollo-tls-secret -n apollo-airlines-apps -o name 2>/dev/null || true)"
  gw_https_res="$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.listeners[?(@.name=="https")].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null || true)"
  https_code="000"
  if [[ -n "${tls_exists}" ]]; then
    ca_tmp="$(mktemp)"
    if kube get secret apollo-tls-secret -n apollo-airlines-apps -o jsonpath='{.data.tls\.crt}' | base64 -d > "${ca_tmp}" 2>/dev/null; then
      https_code="$(curl -s -o /dev/null -w '%{http_code}' --cacert "${ca_tmp}" --resolve "identity.apollo.local:443:${eg_ip}" --connect-timeout 3 "https://identity.apollo.local/healthz" 2>/dev/null || echo '000')"
    fi
    rm -f "${ca_tmp}"
  fi
  if [[ -n "${tls_exists}" && "${gw_https_res}" == "True" && "${https_code}" == "200" ]]; then
    printf '[PASS] TLS Secret present, Gateway HTTPS ResolvedRefs=True, and trusted HTTPS check returned 200\n'
  else
    printf '[FAIL] TLS check failed (secret=%s, listener_ResolvedRefs=%s, HTTPS=%s)\n' "${tls_exists:-missing}" "${gw_https_res:-none}" "${https_code}" >&2
    : $((failures+=1))
  fi

  # 4. Check ReferenceGrant & cross-namespace HTTPRoute
  local rg_exists cross_res cross_code
  rg_exists="$(kube get referencegrant apollo-gateway-grant -n apollo-airlines-ui -o name 2>/dev/null || true)"
  cross_res="$(kube get httproute frontend-cross-ns -n apollo-airlines-apps -o jsonpath='{.status.parents[*].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null || true)"
  cross_code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: cross-ns.apollo.local' --connect-timeout 3 "http://${eg_ip}/" 2>/dev/null || echo '000')"
  if [[ -n "${rg_exists}" && "${cross_res}" == *"True"* && "${cross_res}" != *"False"* && "${cross_code}" == "200" ]]; then
    printf '[PASS] ReferenceGrant present, frontend-cross-ns ResolvedRefs=True, and cross-ns.apollo.local returned 200\n'
  else
    printf '[FAIL] Cross-namespace ReferenceGrant check failed (grant=%s, ResolvedRefs=%s, HTTP=%s)\n' "${rg_exists:-missing}" "${cross_res:-none}" "${cross_code}" >&2
    : $((failures+=1))
  fi

  if [[ "${failures}" -gt 0 ]]; then
    printf '\nVerification failed (%d issue(s)). Continue investigating or run --restore.\n' "${failures}" >&2
    return 1
  fi

  rm -f "${STATE_FILE}"
  rm -rf "${BACKUP_DIR}"
  printf '\nStage 2 fault drill verification succeeded.\n'
}

restore_state() {
  require_stage2_substage5

  kube apply -f "${STAGE_DIR}/k8s/apps/identity/identity-svc.yaml" >/dev/null
  kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/07-httproute-frontend.yaml" >/dev/null
  kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml" >/dev/null
  kube apply -f "${STAGE_DIR}/k8s/substages/05-envoy-gateway/08-httproute-cross-ns-refgrant.yaml" >/dev/null

  if ! kube get secret apollo-tls-secret -n apollo-airlines-apps >/dev/null 2>&1; then
    if [[ -f "${BACKUP_DIR}/apollo-tls-secret.json" ]]; then
      kube apply -f "${BACKUP_DIR}/apollo-tls-secret.json" >/dev/null
    else
      bash "${STAGE_DIR}/k8s/substages/03-traefik-ingress-tls/generate-certs.sh" --context "${CONTEXT}" >/dev/null
    fi
  fi

  rm -f "${STATE_FILE}"
  rm -rf "${BACKUP_DIR}"
  printf 'Stage 2 state restored cleanly on context %s.\n' "${CONTEXT}"
}

case "${ACTION}" in
  inject)
    idx=$((RANDOM % ${#FAULTS[@]}))
    inject_fault "${FAULTS[$idx]}"
    ;;
  inject-id)
    inject_fault "${INJECT_ID}"
    ;;
  verify)
    verify_recovery
    ;;
  restore)
    restore_state
    ;;
esac
