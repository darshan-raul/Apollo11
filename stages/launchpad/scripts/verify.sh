#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$STAGE_DIR/docker-compose.yml"
ENV_FILE="${LAUNCHPAD_ENV_FILE:-$STAGE_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  echo "Copy $STAGE_DIR/.env.example to $STAGE_DIR/.env and change its values."
  exit 1
fi

for command_name in docker curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name"
    exit 1
  fi
done

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
passes=0
failures=0

pass() {
  passes=$((passes + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

check_equal() {
  local description="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$description"
  else
    fail "$description (expected '$expected', got '$actual')"
  fi
}

check_contains() {
  local description="$1"
  local value="$2"
  local expected="$3"
  if [[ "$value" == *"$expected"* ]]; then
    pass "$description"
  else
    fail "$description (missing '$expected')"
  fi
}

default_services="$("${compose[@]}" config --services 2>/dev/null)"
check_equal "default profile has ten workloads" "$(wc -w <<<"$default_services" | tr -d ' ')" "10"
if grep -qx dozzle <<<"$default_services"; then
  fail "Dozzle is excluded from the default profile"
else
  pass "Dozzle is excluded from the default profile"
fi

all_services="$("${compose[@]}" --profile tools config --services 2>/dev/null)"
if grep -qx dozzle <<<"$all_services"; then
  pass "tools profile contains Dozzle"
else
  fail "tools profile contains Dozzle"
fi

app_services=(identity flight booking search notification frontend)
app_ports=(8080 8081 8082 8083 8084 3000)

for index in "${!app_services[@]}"; do
  service="${app_services[$index]}"
  port="${app_ports[$index]}"
  container_id="$("${compose[@]}" ps -q "$service")"
  if [[ -z "$container_id" ]]; then
    fail "$service container exists"
    continue
  fi

  health_status="$(docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null)"
  check_equal "$service is healthy" "$health_status" "healthy"

  runtime_uid="$("${compose[@]}" exec -T "$service" id -u 2>/dev/null)"
  if [[ "$runtime_uid" =~ ^[0-9]+$ ]] && (( runtime_uid > 0 )); then
    pass "$service runs as non-root"
  else
    fail "$service runs as non-root (uid '$runtime_uid')"
  fi

  read_only="$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$container_id" 2>/dev/null)"
  check_equal "$service root filesystem is read-only" "$read_only" "true"

  security_options="$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$container_id" 2>/dev/null)"
  check_contains "$service blocks privilege escalation" "$security_options" "no-new-privileges:true"

  dropped_capabilities="$(docker inspect --format '{{json .HostConfig.CapDrop}}' "$container_id" 2>/dev/null)"
  check_contains "$service drops Linux capabilities" "$dropped_capabilities" "ALL"

  tmpfs_mounts="$(docker inspect --format '{{json .HostConfig.Tmpfs}}' "$container_id" 2>/dev/null)"
  check_contains "$service has a writable /tmp tmpfs" "$tmpfs_mounts" '"/tmp"'

  health_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/healthz" || true)"
  ready_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/readyz" || true)"
  check_equal "$service /healthz returns 200" "$health_code" "200"
  check_equal "$service /readyz returns 200" "$ready_code" "200"

  metrics="$(curl -fsS "http://127.0.0.1:$port/metrics" 2>/dev/null || true)"
  check_contains "$service exposes Prometheus request metrics" "$metrics" "http_requests_total"
  check_contains "$service exposes Prometheus duration metrics" "$metrics" "http_request_duration_ms"
  check_contains "$service exposes Prometheus DB metrics" "$metrics" "db_connections_active"
done

login_response="$(curl -fsS -X POST http://127.0.0.1:8080/api/users/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || true)"
token="$(jq -r '.token // empty' <<<"$login_response" 2>/dev/null)"
if [[ -n "$token" ]]; then
  pass "seeded passenger can log in"
else
  fail "seeded passenger can log in"
fi

flight_count="$("${compose[@]}" exec -T flight-db sh -c 'psql -U "$POSTGRES_USER" -d flight -t -c "SELECT COUNT(*) FROM flights;"' 2>/dev/null | tr -d '[:space:]')"
if [[ "$flight_count" =~ ^[0-9]+$ ]] && (( flight_count >= 186 )); then
  pass "flight table contains full 30-day schedule ($flight_count rows >= 186)"
else
  fail "flight table contains full 30-day schedule (got '$flight_count', expected >= 186)"
fi

request_id="launchpad-verify-$RANDOM-$RANDOM"
booking_response="$(curl -fsS -X POST http://127.0.0.1:8082/api/bookings \
  -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' \
  -H "X-Request-ID: $request_id" \
  -d '{"flightId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}' 2>/dev/null || true)"
booking_id="$(jq -r '.id // empty' <<<"$booking_response" 2>/dev/null)"
booking_status="$(jq -r '.status // empty' <<<"$booking_response" 2>/dev/null)"
check_equal "flagship workflow creates a confirmed booking" "$booking_status" "CONFIRMED"

if [[ -n "$booking_id" ]]; then
  cancel_code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
    "http://127.0.0.1:8082/api/bookings/$booking_id" \
    -H "Authorization: Bearer $token" \
    -H "X-Request-ID: $request_id" || true)"
  check_equal "verification booking is cancelled" "$cancel_code" "200"
else
  fail "verification booking is cancelled (booking ID missing)"
fi

sleep 1
workflow_logs="$("${compose[@]}" logs booking identity flight notification 2>/dev/null)"
if grep -q "$request_id" <<<"$workflow_logs"; then
  pass "flagship request ID appears in service logs"
else
  fail "flagship request ID appears in service logs"
fi

printf '\nLaunchpad verification: %d passed, %d failed\n' "$passes" "$failures"
if (( failures > 0 )); then
  exit 1
fi
