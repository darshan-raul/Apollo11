#!/usr/bin/env bash
# Bounded booking-creation outage; restore Flight and cancel the recovery booking.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/context.sh"
apollo_context_guard
NS=apollo-airlines-apps
POD="apollo-slo-$RANDOM"
ORIGINAL_REPLICAS=$(kubectl get deployment flight -n "$NS" -o jsonpath='{.spec.replicas}')
BOOKING_ID=""
TOKEN=""
RESTORED=false
client() { kubectl exec -n "$NS" "$POD" -- curl --max-time 15 "$@"; }
cleanup() {
  local result=$?
  if [[ "$RESTORED" != true ]]; then
    kubectl scale deployment/flight -n "$NS" --replicas="$ORIGINAL_REPLICAS" >&2 || result=1
    kubectl rollout status deployment/flight -n "$NS" --timeout=120s >&2 || result=1
  fi
  if [[ -n "$BOOKING_ID" ]]; then
    client -fsS -X DELETE -H "Authorization: Bearer $TOKEN" "http://booking:8082/api/bookings/$BOOKING_ID" >/dev/null || result=1
  fi
  kubectl delete pod "$POD" -n "$NS" --ignore-not-found --wait=false >/dev/null || result=1
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
kubectl run "$POD" -n "$NS" --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 900 >/dev/null
kubectl wait --for=condition=Ready pod/"$POD" -n "$NS" --timeout=120s >/dev/null
login=$(client -fsS -H 'Content-Type: application/json' \
  -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' http://identity:8080/api/users/login)
TOKEN=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<< "$login")
flights=$(client -fsS http://flight:8081/api/flights)
FLIGHT_ID=$(python3 -c 'import json,sys; d=json.load(sys.stdin); fs=d["flights"] if "flights" in d else d["data"]; print(next(f["id"] for f in fs if f["status"] == "SCHEDULED" and f["availableSeats"] > 0))' <<< "$flights")
# Confirm the baseline with a real booking, then cancel before inducing failure.
create_booking() {
  client -sS -w $'\n%{http_code}' -X POST -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" -d "{\"flightId\":\"$FLIGHT_ID\"}" http://booking:8082/api/bookings
}
response=$(create_booking)
[[ "${response##*$'\n'}" =~ ^20[01]$ ]] || { echo 'Baseline booking failed' >&2; exit 1; }
BOOKING_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "${response%$'\n'*}")
client -fsS -X DELETE -H "Authorization: Bearer $TOKEN" "http://booking:8082/api/bookings/$BOOKING_ID" >/dev/null
BOOKING_ID=""
kubectl scale deployment/flight -n "$NS" --replicas=0 >/dev/null
kubectl rollout status deployment/flight -n "$NS" --timeout=120s >/dev/null
echo 'Generating 502 booking attempts for 150 seconds; inspect the pending/firing burn alert.'
end=$((SECONDS + 150))
while [[ "$SECONDS" -lt "$end" ]]; do
  response=$(create_booking)
  [[ "${response##*$'\n'}" == 502 ]] || { echo "Expected 502, got ${response##*$'\n'}" >&2; exit 1; }
  sleep 1
done
kubectl scale deployment/flight -n "$NS" --replicas="$ORIGINAL_REPLICAS" >/dev/null
kubectl rollout status deployment/flight -n "$NS" --timeout=120s >/dev/null
RESTORED=true
response=$(create_booking)
[[ "${response##*$'\n'}" =~ ^20[01]$ ]] || { echo 'Recovery booking failed' >&2; exit 1; }
BOOKING_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "${response%$'\n'*}")
client -fsS -X DELETE -H "Authorization: Bearer $TOKEN" "http://booking:8082/api/bookings/$BOOKING_ID" >/dev/null
BOOKING_ID=""
echo 'Recovery proved by a successful booking and cancellation. Waiting for the next scrape/rule evaluation.'
sleep 35
for query in 'apollo:booking_error_ratio:5m' 'apollo:booking_error_budget_remaining:28d'; do
  client -fsS -G --data-urlencode "query=$query" http://prometheus.apollo-observability:9090/api/v1/query \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="success" and d["data"]["result"],d; print(d["data"]["result"])'
done
echo 'The error ratio falls as failures leave the short window; cumulative budget spending remains in the longer window.'
