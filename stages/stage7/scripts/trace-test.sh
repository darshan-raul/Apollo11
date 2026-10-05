#!/bin/bash
# Prove that one booking request forms a single cross-service Tempo trace.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/context.sh"
apollo_context_guard

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

DEBUG_POD="stage7-trace-$RANDOM"
cleanup() { kubectl delete pod "$DEBUG_POD" -n apollo-airlines-apps --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

step "Starting an in-cluster HTTP client"
kubectl run "$DEBUG_POD" -n apollo-airlines-apps --image=curlimages/curl:8.10.1 \
    --restart=Never --command -- sleep 600 >/dev/null
kubectl wait --for=condition=Ready pod/"$DEBUG_POD" -n apollo-airlines-apps --timeout=120s >/dev/null || fail "debug pod did not become ready"

step "Authenticating and selecting a seeded flight"
login=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -fsS \
    -H 'Content-Type: application/json' -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' \
    http://identity:8080/api/users/login)
token=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' <<<"$login")
[[ -n "$token" ]] || fail "login did not return a token"
flights=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -fsS http://flight:8081/api/flights)
mapfile -t flight_ids < <(grep -o '"id":"[^"]*"' <<<"$flights" | sed 's/"id":"//;s/"$//')
[[ "${#flight_ids[@]}" -gt 0 ]] || fail "seeded flight not found"

TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)
REQUEST_ID="stage7-$TRACE_ID"
step "Creating a booking with trace_id=$TRACE_ID"
booking=""
chosen_flight_id=""
seats_before=""
for flight_id in "${flight_ids[@]}"; do
    flight_before=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -fsS "http://flight:8081/api/flights/$flight_id")
    candidate_seats=$(sed -n 's/.*"availableSeats":\([0-9][0-9]*\).*/\1/p' <<<"$flight_before")
    response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -sS -w $'\n%{http_code}' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $token" \
        -H "X-Request-ID: $REQUEST_ID" \
        -H "traceparent: 00-$TRACE_ID-$SPAN_ID-01" \
        -d "{\"flightId\":\"$flight_id\"}" \
        http://booking:8082/api/bookings)
    status=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "$status" == "200" || "$status" == "201" ]] && grep -q '"bookingReference"' <<<"$body"; then
        booking="$body"
        chosen_flight_id="$flight_id"
        seats_before="$candidate_seats"
        break
    fi
    [[ "$status" == "409" ]] || fail "booking request returned HTTP $status: $body"
done
[[ -n "$booking" ]] || fail "all seeded flights are already booked for the trace-test user"
[[ "$seats_before" =~ ^[0-9]+$ ]] || fail "could not read available seats before booking"
flight_after_create=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -fsS "http://flight:8081/api/flights/$chosen_flight_id")
seats_after_create=$(sed -n 's/.*"availableSeats":\([0-9][0-9]*\).*/\1/p' <<<"$flight_after_create")
[[ "$seats_after_create" -eq $((seats_before - 1)) ]] || fail "seat count did not decrement after booking ($seats_before -> $seats_after_create)"

step "Waiting for Tempo to contain the cross-service span graph"
trace_json=""
for _ in $(seq 1 20); do
    trace_json=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- \
        curl -fsS "http://tempo.apollo-observability.svc.cluster.local:3100/api/traces/$TRACE_ID" 2>/dev/null || true)
    if [[ -n "$trace_json" ]] && grep -q 'booking' <<<"$trace_json" && \
       grep -q 'identity' <<<"$trace_json" && grep -q 'flight' <<<"$trace_json" && \
       grep -q 'notification' <<<"$trace_json"; then
        break
    fi
    sleep 3
done
[[ -n "$trace_json" ]] || fail "Tempo did not return trace $TRACE_ID"
for service in booking identity flight notification; do
    grep -q "$service" <<<"$trace_json" || fail "trace $TRACE_ID is missing service $service"
done

python3 - "$TRACE_ID" "$trace_json" <<'PY'
import json, sys
trace_id, payload = sys.argv[1], json.loads(sys.argv[2])
services = set()
def visit(value):
    if isinstance(value, dict):
        attrs = value.get("attributes")
        if isinstance(attrs, list):
            for attr in attrs:
                if attr.get("key") == "service.name":
                    services.add(str(attr.get("value", {}).get("stringValue", "")))
        for child in value.values(): visit(child)
    elif isinstance(value, list):
        for child in value: visit(child)
visit(payload)
print(f"trace_id={trace_id} services={','.join(sorted(filter(None, services)))}")
PY

booking_id=$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' <<<"$booking")
[[ -n "$booking_id" ]] || fail "created booking response did not contain an id"
step "Cancelling the passenger booking and restoring its seat"
cancel_response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -sS -w $'\n%{http_code}' \
    -X DELETE -H "Authorization: Bearer $token" \
    -H "X-Request-ID: $REQUEST_ID-cancel" \
    "http://booking:8082/api/bookings/$booking_id")
cancel_status=${cancel_response##*$'\n'}
cancel_body=${cancel_response%$'\n'*}
[[ "$cancel_status" == "200" ]] || fail "booking cancellation returned HTTP $cancel_status: $cancel_body"

seats_after_cancel=""
for _ in $(seq 1 20); do
    flight_after_cancel=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- curl -fsS "http://flight:8081/api/flights/$chosen_flight_id")
    seats_after_cancel=$(sed -n 's/.*"availableSeats":\([0-9][0-9]*\).*/\1/p' <<<"$flight_after_cancel")
    [[ "$seats_after_cancel" == "$seats_before" ]] && break
    sleep 1
done
[[ "$seats_after_cancel" == "$seats_before" ]] || fail "seat count was not restored after cancellation ($seats_before -> $seats_after_cancel)"

ok "passenger booking and cancellation succeeded; one trace contains booking → identity → flight → notification"
