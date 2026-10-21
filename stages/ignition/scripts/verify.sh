#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${STAGE_DIR}/pod.yaml"
CONTEXT="${1:-$(kubectl config current-context 2>/dev/null || true)}"
PASSED=0
FAILED=0

pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "${description}"
  else
    fail "${description}"
  fi
}

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

wait_for_restart() {
  local before="$1"
  local current
  for _ in $(seq 1 30); do
    current="$(kube get pod apollo-shell -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)"
    if [[ "${current:-0}" -gt "${before}" ]]; then
      kube wait --for=condition=Ready pod/apollo-shell --timeout=60s >/dev/null 2>&1
      return $?
    fi
    sleep 1
  done
  return 1
}

wait_for_absence() {
  for _ in $(seq 1 5); do
    if ! kube get pod apollo-shell >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

printf 'Ignition verification on context %s\n' "${CONTEXT:-<none>}"

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev|kind-apollo11-ignition-verify) ;;
  *)
    printf 'Refusing to mutate context %s; expected an Ignition-owned kind context.\n' "${CONTEXT:-<none>}" >&2
    exit 2
    ;;
esac

check 'manifest passes client-side validation' kube apply --dry-run=client -f "${MANIFEST}"
check 'cluster API is reachable' kube cluster-info

check 'all cluster nodes become Ready' \
  kube wait --for=condition=Ready nodes --all --timeout=120s

if kube get pod apollo-shell >/dev/null 2>&1; then
  existing_stage="$(kube get pod apollo-shell -o jsonpath='{.metadata.labels.stage}' 2>/dev/null || true)"
  if [[ "${existing_stage}" != 'ignition' ]]; then
    printf 'Refusing to replace existing default/apollo-shell without the stage=ignition label.\n' >&2
    exit 2
  fi
fi

if ! kube apply -f "${MANIFEST}" >/dev/null 2>&1; then
  fail 'declarative manifest applies cleanly'
  printf '\nIgnition verification: %d passed, %d failed\n' "${PASSED}" "${FAILED}"
  exit 1
fi

if kube wait --for=condition=Ready pod/apollo-shell --timeout=90s >/dev/null 2>&1; then
  pass 'declarative Pod becomes Ready'
else
  fail 'declarative Pod becomes Ready'
  kube get pod apollo-shell -o wide >&2 || true
  kube get events \
    --field-selector involvedObject.name=apollo-shell \
    --sort-by=.metadata.creationTimestamp >&2 || true
  printf '\nIgnition verification: %d passed, %d failed\n' "${PASSED}" "${FAILED}"
  exit 1
fi
check 'Pod carries the ignition stage label' test "$(kube get pod apollo-shell -o jsonpath='{.metadata.labels.stage}' 2>/dev/null)" = 'ignition'
check 'Pod uses restartPolicy Always' test "$(kube get pod apollo-shell -o jsonpath='{.spec.restartPolicy}' 2>/dev/null)" = 'Always'
check 'healthy Pod serves the expected response' test "$(kube exec apollo-shell -- wget -qO- http://127.0.0.1:8080/ 2>/dev/null)" = 'Apollo11 Ignition ready'

original_uid="$(kube get pod apollo-shell -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
original_restarts="$(kube get pod apollo-shell -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || printf '0')"
kube exec apollo-shell -- sh -c 'kill "$(pidof httpd)"' >/dev/null 2>&1 || true

if wait_for_restart "${original_restarts:-0}"; then
  pass 'kubelet restarts the crashed container'
else
  fail 'kubelet restarts the crashed container'
fi

check 'container restart preserves the Pod UID' test "$(kube get pod apollo-shell -o jsonpath='{.metadata.uid}' 2>/dev/null)" = "${original_uid}"
check 'restarted container recovers HTTP behavior' test "$(kube exec apollo-shell -- wget -qO- http://127.0.0.1:8080/ 2>/dev/null)" = 'Apollo11 Ignition ready'

kube delete pod apollo-shell --wait=true >/dev/null 2>&1
if wait_for_absence; then
  pass 'deleted bare Pod stays absent without a controller'
else
  fail 'deleted bare Pod stays absent without a controller'
fi

kube apply -f "${MANIFEST}" >/dev/null 2>&1
check 'reapplied Pod becomes Ready' kube wait --for=condition=Ready pod/apollo-shell --timeout=90s
replacement_uid="$(kube get pod apollo-shell -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"

if [[ -n "${replacement_uid}" ]] && [[ "${replacement_uid}" != "${original_uid}" ]]; then
  pass 'reapplied Pod receives a new UID'
else
  fail 'reapplied Pod receives a new UID'
fi

check 'reapplied Pod recovers HTTP behavior' test "$(kube exec apollo-shell -- wget -qO- http://127.0.0.1:8080/ 2>/dev/null)" = 'Apollo11 Ignition ready'

printf '\nIgnition verification: %d passed, %d failed\n' "${PASSED}" "${FAILED}"
[[ "${FAILED}" -eq 0 ]]
