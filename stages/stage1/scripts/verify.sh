#!/usr/bin/env bash

set -uo pipefail

usage() {
  printf 'Usage: %s [--context kind-apollo11|kind-apollo11-dev] [kind-apollo11|kind-apollo11-dev]\n' "$0"
  printf '  --context CTX  Kubernetes context (or set KUBE_CONTEXT)\n'
}

CONTEXT="${KUBE_CONTEXT:-}"
CONTEXT_SET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ "${CONTEXT_SET}" == false && -z "${CONTEXT}" ]]; then
  CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi
NAMESPACE=apollo-airlines
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "${description}"; else fail "${description}"; fi
}

check_equal() {
  local description="$1" actual="$2" expected="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    pass "${description}"
  else
    fail "${description} (expected '${expected}', got '${actual}')"
  fi
}

check_contains() {
  local description="$1" actual="$2" expected="$3"
  if [[ "${actual}" == *"${expected}"* ]]; then
    pass "${description}"
  else
    fail "${description} (missing '${expected}')"
  fi
}

kube() { kubectl --context "${CONTEXT}" "$@"; }

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; expected a Stage 1 kind context.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

for command in kubectl curl jq; do
  check "${command} is installed" command -v "${command}"
done
check 'cluster API is reachable' kube cluster-info
check 'apollo-airlines namespace exists' kube get namespace "${NAMESPACE}"
check 'application ConfigMap exists' kube get configmap apollo-airlines-config -n "${NAMESPACE}"
check 'application Secret exists' kube get secret apollo-airlines-secrets -n "${NAMESPACE}"

service_accounts=(
  identity-db flight-db booking-db redis
  identity flight booking search notification frontend
  init-identity-db init-flight-db init-booking-db
)
for account in "${service_accounts[@]}"; do
  check "ServiceAccount ${account} exists" kube get serviceaccount "${account}" -n "${NAMESPACE}"
  automount="$(kube get serviceaccount "${account}" -n "${NAMESPACE}" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || true)"
  check_equal "ServiceAccount ${account} disables token automount" "${automount}" 'false'
  permission="$(kube auth can-i get pods --as="system:serviceaccount:${NAMESPACE}:${account}" -n "${NAMESPACE}" 2>/dev/null || true)"
  check_equal "ServiceAccount ${account} cannot read Pods" "${permission}" 'no'
done

deployments=(identity-db flight-db booking-db redis identity flight booking search notification frontend)
expected_replicas=(1 1 1 1 2 2 2 2 2 2)
for index in "${!deployments[@]}"; do
  deployment="${deployments[$index]}"
  expected="${expected_replicas[$index]}"
  check "Deployment ${deployment} exists" kube get deployment "${deployment}" -n "${NAMESPACE}"
  replicas="$(kube get deployment "${deployment}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  available="$(kube get deployment "${deployment}" -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  account="$(kube get deployment "${deployment}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || true)"
  check_equal "Deployment ${deployment} desired replicas" "${replicas}" "${expected}"
  check_equal "Deployment ${deployment} available replicas" "${available:-0}" "${expected}"
  check_equal "Deployment ${deployment} uses its own identity" "${account}" "${deployment}"
  pod="$(kube get pod -n "${NAMESPACE}" -l "app=${deployment}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  check "Pod ${pod:-<missing>} has no API token file" kube exec -n "${NAMESPACE}" "${pod}" -- test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token
done

services=(identity-db flight-db booking-db redis identity flight booking search notification frontend)
service_ports=(5432 5432 5432 6379 8080 8081 8082 8083 8084 3000)
for index in "${!services[@]}"; do
  service="${services[$index]}"
  expected_port="${service_ports[$index]}"
  port="$(kube get service "${service}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
  selector="$(kube get service "${service}" -n "${NAMESPACE}" -o jsonpath='{.spec.selector.app}' 2>/dev/null || true)"
  endpoint="$(kube get endpoints "${service}" -n "${NAMESPACE}" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
  check_equal "Service ${service} exposes port ${expected_port}" "${port}" "${expected_port}"
  check_equal "Service ${service} selects app=${service}" "${selector}" "${service}"
  if [[ -n "${endpoint}" ]]; then pass "Service ${service} has a ready endpoint"; else fail "Service ${service} has a ready endpoint"; fi
done

for job in init-identity-db init-flight-db init-booking-db; do
  complete="$(kube get job "${job}" -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  account="$(kube get job "${job}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || true)"
  check_equal "Job ${job} completed" "${complete:-0}" '1'
  check_equal "Job ${job} uses its own identity" "${account}" "${job}"
done

identity_rows="$(kube exec -n "${NAMESPACE}" deployment/identity-db -- \
  psql -U postgres -d identity -tAc 'SELECT count(*) FROM users;' 2>/dev/null || true)"
flight_rows="$(kube exec -n "${NAMESPACE}" deployment/flight-db -- \
  psql -U postgres -d flight -tAc 'SELECT count(*) FROM flights;' 2>/dev/null || true)"
booking_table="$(kube exec -n "${NAMESPACE}" deployment/booking-db -- \
  psql -U postgres -d booking -tAc "SELECT to_regclass('public.bookings');" 2>/dev/null || true)"
check_equal 'identity Job seeds two users' "${identity_rows}" '2'
check_equal 'flight Job seeds six routes across 31 days' "${flight_rows}" '186'
check_equal 'booking Job creates the bookings table' "${booking_table}" 'bookings'

app_names=(identity flight booking search frontend)
app_ports=(30083 30081 30082 30084 30080)
for index in "${!app_names[@]}"; do
  app="${app_names[$index]}"
  port="${app_ports[$index]}"
  health="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/healthz" || true)"
  ready="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/readyz" || true)"
  metrics="$(curl -fsS "http://127.0.0.1:${port}/metrics" 2>/dev/null || true)"
  check_equal "${app} health endpoint returns 200" "${health}" '200'
  check_equal "${app} readiness endpoint returns 200" "${ready}" '200'
  check_contains "${app} exposes Prometheus metrics" "${metrics}" 'http_requests_total'
done

login_response="$(curl -fsS -X POST http://127.0.0.1:30083/api/users/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || true)"
token="$(jq -r '.token // empty' <<<"${login_response}" 2>/dev/null)"
if [[ -n "${token}" ]]; then pass 'seeded passenger can log in'; else fail 'seeded passenger can log in'; fi

flights_response="$(curl -fsS http://127.0.0.1:30081/api/flights 2>/dev/null || true)"
flight_id="$(jq -r '.flights[0].id // empty' <<<"${flights_response}" 2>/dev/null)"
if [[ -n "${flight_id}" ]]; then pass 'seeded flight inventory is queryable'; else fail 'seeded flight inventory is queryable'; fi

request_id="stage1-verify-${RANDOM}-${RANDOM}"
booking_response="$(curl -fsS -X POST http://127.0.0.1:30082/api/bookings \
  -H "Authorization: Bearer ${token}" \
  -H 'Content-Type: application/json' \
  -H "X-Request-ID: ${request_id}" \
  -d "{\"flightId\":\"${flight_id}\"}" 2>/dev/null || true)"
booking_id="$(jq -r '.id // empty' <<<"${booking_response}" 2>/dev/null)"
booking_status="$(jq -r '.status // empty' <<<"${booking_response}" 2>/dev/null)"
check_equal 'flagship workflow creates a confirmed booking' "${booking_status}" 'CONFIRMED'
if [[ -n "${booking_id}" ]]; then
  cancel_code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
    "http://127.0.0.1:30082/api/bookings/${booking_id}" \
    -H "Authorization: Bearer ${token}" \
    -H "X-Request-ID: ${request_id}" || true)"
  check_equal 'verification booking is cancelled' "${cancel_code}" '200'
else
  fail 'verification booking is cancelled (booking ID missing)'
fi

sleep 1
for service in booking flight notification; do
  service_logs="$(kube logs -n "${NAMESPACE}" -l "app=${service}" --prefix=true --tail=200 2>/dev/null || true)"
  check_contains "${service} logs carry the flagship request ID" "${service_logs}" "${request_id}"
done

old_booking_pod="$(kube get pod -n "${NAMESPACE}" -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${old_booking_pod}" ]]; then
  old_booking_uid="$(kube get pod "${old_booking_pod}" -n "${NAMESPACE}" -o jsonpath='{.metadata.uid}')"
  kube delete pod "${old_booking_pod}" -n "${NAMESPACE}" --wait=true >/dev/null 2>&1
  check 'booking Deployment returns to two available replicas' kube rollout status deployment/booking -n "${NAMESPACE}" --timeout=120s
  new_booking_uids="$(kube get pods -n "${NAMESPACE}" -l app=booking -o jsonpath='{.items[*].metadata.uid}')"
  if [[ " ${new_booking_uids} " != *" ${old_booking_uid} "* ]]; then pass 'ReplicaSet replaces the deleted booking Pod'; else fail 'ReplicaSet replaces the deleted booking Pod'; fi
else
  fail 'ReplicaSet replaces the deleted booking Pod (no booking pod found)'
fi
check_equal 'booking stays behaviorally ready after Pod replacement' "$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:30082/readyz || true)" '200'

original_image="$(kube get deployment search -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
kube rollout restart deployment/search -n "${NAMESPACE}" >/dev/null
check 'successful search rollout completes' kube rollout status deployment/search -n "${NAMESPACE}" --timeout=120s
history_count="$(kube rollout history deployment/search -n "${NAMESPACE}" 2>/dev/null | awk '/^[0-9]+/ {count++} END {print count+0}')"
if [[ "${history_count}" -ge 2 ]]; then pass 'successful rollout creates ReplicaSet history'; else fail 'successful rollout creates ReplicaSet history'; fi

kube set image deployment/search search=apollo11/search:missing-stage1-demo -n "${NAMESPACE}" >/dev/null
bad_reason=''
for _ in $(seq 1 60); do
  bad_reason="$(kube get pods -n "${NAMESPACE}" -l app=search -o jsonpath='{range .items[*].status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}' 2>/dev/null || true)"
  if [[ "${bad_reason}" == *'ImagePullBackOff'* || "${bad_reason}" == *'ErrImagePull'* ]]; then break; fi
  sleep 2
done
if [[ "${bad_reason}" == *'ImagePullBackOff'* || "${bad_reason}" == *'ErrImagePull'* ]]; then pass 'bad image produces an observable pull failure'; else fail 'bad image produces an observable pull failure'; fi
available="$(kube get deployment search -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
if [[ "${available:-0}" -ge 1 ]]; then pass 'rolling update keeps an old search replica available'; else fail 'rolling update keeps an old search replica available'; fi
kube rollout undo deployment/search -n "${NAMESPACE}" >/dev/null 2>&1
check 'rollback completes' kube rollout status deployment/search -n "${NAMESPACE}" --timeout=120s
restored_image="$(kube get deployment search -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
check_equal 'rollback restores the working image' "${restored_image}" "${original_image}"
check_equal 'search recovers behavior after rollback' "$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:30084/readyz || true)" '200'

printf '\nStage 1 verification: %d passed, %d failed\n' "${PASSED}" "${FAILED}"
[[ "${FAILED}" -eq 0 ]]
