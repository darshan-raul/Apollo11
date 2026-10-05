#!/usr/bin/env bash
# Validate certificate trust/hostname, HTTPS API workflow, and reversible booking.
set -euo pipefail
CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
case "$CONTEXT" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) echo "Refusing HTTPS workflow in context '${CONTEXT:-<none>}'" >&2; exit 2 ;;
esac
SECRET_NAME=apollo-edge-tls
kube() { kubectl --context "$CONTEXT" "$@"; }
CA_FILE=$(mktemp)
BOOKING_ID=""
TOKEN=""
IP=$(kube -n envoy-gateway-system get service -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
[[ -n "$IP" ]] || { echo 'Gateway has no LoadBalancer address' >&2; rm -f "$CA_FILE"; exit 1; }
route() {
  local host="$1" path="$2"; shift 2
  curl --max-time 15 --cacert "$CA_FILE" --resolve "$host:443:$IP" "$@" "https://$host$path"
}
cleanup() {
  local result=$?
  if [[ -n "$BOOKING_ID" ]]; then
    route booking.apollo.local "/api/bookings/$BOOKING_ID" -fsS -X DELETE \
      -H "Authorization: Bearer $TOKEN" >/dev/null || result=1
  fi
  rm -f "$CA_FILE"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
kube -n apollo-airlines-apps get secret "$SECRET_NAME" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CA_FILE"
for host in identity flight booking search; do
  route "$host.apollo.local" /healthz -fsS >/dev/null
  echo "Trusted HTTPS health: $host"
done
route frontend.apollo.local / -fsS >/dev/null
set +e
curl -sS --max-time 15 --cacert "$CA_FILE" --resolve "untrusted.apollo.invalid:443:$IP" \
  https://untrusted.apollo.invalid/healthz >/dev/null 2>&1
negative_result=$?
set -e
[[ "$negative_result" == 60 ]] || { echo "Expected hostname verification failure (60), got $negative_result" >&2; exit 1; }
login=$(route identity.apollo.local /api/users/login -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"email":"passenger@apolloairlines.com","password":"pass123"}')
TOKEN=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' <<< "$login")
flights=$(route flight.apollo.local /api/flights -fsS)
flight=$(python3 -c 'import json,sys; print(json.dumps(next(f for f in json.load(sys.stdin)["flights"] if f["status"]=="SCHEDULED" and f["availableSeats"]>0)))' <<< "$flights")
FLIGHT_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$flight")
search_path=$(python3 -c 'import json,sys,urllib.parse; f=json.load(sys.stdin); print("/api/search?"+urllib.parse.urlencode(dict(origin=f["origin"],destination=f["destination"],date=f["departureTime"][:10])))' <<< "$flight")
route search.apollo.local "$search_path" -fsS | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["results"] and d["total"]>0,d'
booking=$(route booking.apollo.local /api/bookings -fsS -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" -d "{\"flightId\":\"$FLIGHT_ID\"}")
BOOKING_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$booking")
route booking.apollo.local "/api/bookings/$BOOKING_ID" -fsS -X DELETE -H "Authorization: Bearer $TOKEN" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("message")=="Booking cancelled",d'
route booking.apollo.local "/api/bookings/$BOOKING_ID" -fsS -H "Authorization: Bearer $TOKEN" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status")=="CANCELLED",d'
BOOKING_ID=""
echo 'Trusted HTTPS login, populated search, booking, cancellation, and hostname rejection passed.'
