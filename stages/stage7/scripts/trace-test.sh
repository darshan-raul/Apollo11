#!/bin/bash
# Trace Test: end-to-end demonstration that the OTEL SDK + Collector + Tempo
# pipeline is working. Run after apply.sh.
#
# What it does:
#   1. Login as admin to identity service (gets JWT)
#   2. POST a booking via booking service
#   3. Extract the X-Request-ID + trace_id from the response
#   4. Poll Tempo's HTTP API for that trace_id
#   5. Print the spans (booking → identity → flight → flight-db → notification)
#
# This is the "single trace demonstrates cross-service propagation" win from
# AGENTS.md §Observability Trace Design.
#
# Usage:
#   ./scripts/trace-test.sh
#   ./scripts/trace-test.sh --service search
#   ./scripts/trace-test.sh --json   # print raw trace JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="booking"
JSON_OUT=false
ADMIN_EMAIL="admin@apolloairlines.com"
ADMIN_PASSWORD="admin123"

usage() {
    cat <<EOF
Usage: $0 [--service NAME] [--json]

Options:
  --service NAME    Which service to call (default: booking).
                    Options: identity, flight, booking, search, notification.
  --json            Print raw trace JSON from Tempo instead of pretty spans.
  --help            Show this help.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --service) SERVICE="$2"; shift 2 ;;
        --json)    JSON_OUT=true; shift ;;
        --help)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Pick a port-forward-friendly access path. We use the in-cluster Service
# DNS, so this only works from a pod in the same cluster. If you want to
# run this from outside, first:
#   kubectl port-forward svc/booking -n apollo-airlines-apps 8082:8082
# then set BASE_URL to http://localhost:8082.

BASE_URL="${BASE_URL:-http://booking:8082}"

step "1/5 Logging in as admin"
# We'll use kubectl exec from inside a debug pod OR port-forward. For
# simplicity we use a temporary busybox pod in the apps namespace.
DEBUG_POD="trace-test-debug-$$"
kubectl run "$DEBUG_POD" -n apollo-airlines-apps \
    --image=curlimages/curl:8.05.1 --restart=Never \
    --rm=true --quiet=true \
    --command -- sleep 600 >/dev/null 2>&1 || true

# Wait for the pod to be ready
for i in $(seq 1 30); do
    if kubectl get pod "$DEBUG_POD" -n apollo-airlines-apps >/dev/null 2>&1; then
        if kubectl get pod "$DEBUG_POD" -n apollo-airlines-apps -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; then
            ok "debug pod ready"
            break
        fi
    fi
    sleep 2
done

login_response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- \
    curl -s -X POST http://identity:8080/api/users/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" 2>/dev/null || echo "{}")
TOKEN=$(echo "$login_response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
    fail "Login failed: $login_response"
fi
ok "got JWT (${#TOKEN} chars)"

step "2/5 Listing flights to find a flight ID"
flights_response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- \
    curl -s "http://flight:8081/api/flights?origin=BOM&destination=DEL" 2>/dev/null || echo "{}")
flight_id=$(echo "$flights_response" | sed -n 's/.*"flights":\[{"id":"\([^"]*\)".*/\1/p')
if [[ -z "$flight_id" ]]; then
    # Try without filter
    flights_response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- \
        curl -s "http://flight:8081/api/flights" 2>/dev/null || echo "{}")
    flight_id=$(echo "$flights_response" | sed -n 's/.*"flights":\[{"id":"\([^"]*\)".*/\1/p')
fi
if [[ -z "$flight_id" ]]; then
    fail "no flight found: $flights_response"
fi
ok "found flight $flight_id"

step "3/5 Creating a booking (this is the multi-service trace)"
booking_response=$(kubectl exec -n apollo-airlines-apps "$DEBUG_POD" -- \
    curl -s -X POST "$BASE_URL/api/bookings" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"flightId\":\"$flight_id\"}" 2>&1 || echo "{}")
TRACE_ID=$(echo "$booking_response" | grep -oE 'trace[Ii]d":"[a-f0-9]+' | head -1 | sed 's/.*"//')
REQUEST_ID=$(echo "$booking_response" | grep -oE 'X-Request-Id[^"]*' | head -1 || echo "")

# The trace_id is in the X-Request-ID header (we use that as a trace
# correlation key in the JSON logger). Real OTEL trace_ids are 32 hex
# chars; the JSON logger prefixes trace_id with the X-Request-ID.
echo "$booking_response" > /tmp/trace-test-booking.json
if [[ -n "$TRACE_ID" ]]; then
    ok "booking created, trace_id=$TRACE_ID"
else
    echo "  booking response: $booking_response"
    fail "could not extract trace_id from booking response"
fi

step "4/5 Polling Tempo for the trace (5 attempts, 3s apart)"
# Wait a moment for the spans to flush
sleep 5
trace_json=""
for i in 1 2 3 4 5; do
    trace_json=$(kubectl exec -n apollo-observability deploy/tempo -- \
        wget -qO- "http://localhost:3100/api/traces/$TRACE_ID" 2>/dev/null || echo "")
    if [[ -n "$trace_json" && "$trace_json" != "[]" && "$trace_json" != "{}" ]]; then
        ok "Tempo returned the trace on attempt $i"
        break
    fi
    sleep 3
done

if [[ -z "$trace_json" || "$trace_json" == "[]" ]]; then
    fail "Tempo did not return trace $TRACE_ID after 5 attempts. Check otel-collector logs."
fi

step "5/5 Trace contents"
if [[ "$JSON_OUT" == "true" ]]; then
    echo "$trace_json" | python3 -m json.tool
else
    # Parse the JSON, print span name + service for each
    python3 - "$trace_json" <<'PY'
import json
import sys

trace = json.loads(sys.argv[1])
traces = trace.get("traces", [])
if not traces:
    print("  No traces returned")
    sys.exit(0)

t = traces[0]
spans = t.get("spans", [])
print(f"  Trace ID: {t.get('traceID', '?')}")
print(f"  Spans: {len(spans)}")
print(f"")
print(f"  {'SERVICE':<20} {'OPERATION':<50} {'DURATION (ms)':<14}")
print(f"  {'-'*20} {'-'*50} {'-'*14}")

for s in spans:
    tags = {t["key"]: t.get("value", "") for t in s.get("tags", [])}
    svc = tags.get("service.name", "unknown")
    op = s.get("operationName", "?")
    start = int(s.get("startTime", 0))
    end = int(s.get("endTime", 0))
    dur = (end - start) / 1000.0  # ns → ms
    print(f"  {svc:<20} {op:<50} {dur:>10.2f} ms")
PY
fi

# Cleanup the debug pod
kubectl delete pod "$DEBUG_POD" -n apollo-airlines-apps --wait=false >/dev/null 2>&1 || true

ok "trace test complete"
echo ""
echo "  Tip: open Grafana → Explore → Tempo and paste trace_id=$TRACE_ID"
echo "  Tip: port-forward Grafana with: kubectl port-forward svc/grafana -n apollo-observability 3000:3000"
