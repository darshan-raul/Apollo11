#!/usr/bin/env bash
# Prove edge failure/recovery and actual firing/resolved notification delivery.
set -euo pipefail
source "$(dirname "$0")/context.sh"
apollo_context_guard
ns=apollo-observability
pod="observe-lab-$RANDOM"
work=$(mktemp -d)
route_saved=false
cleanup() {
  result=$?
  if [[ "$route_saved" == true ]]; then kubectl apply -f "$work/route.yaml" >/dev/null || result=1; fi
  kubectl -n "$ns" delete prometheusrule apollo-delivery-lab --ignore-not-found >/dev/null || result=1
  kubectl -n "$ns" delete pod "$pod" --ignore-not-found --wait=false >/dev/null || result=1
  rm -rf "$work"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash "$(dirname "$0")/edge-probe.sh"
kubectl -n "$ns" run "$pod" --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 900 >/dev/null
kubectl -n "$ns" wait --for=condition=Ready pod/"$pod" --timeout=120s >/dev/null
client() { kubectl -n "$ns" exec "$pod" -- curl --max-time 10 -fsS "$@"; }
probe() {
  local expected=$1 payload
  for _ in $(seq 1 40); do
    payload=$(client -G --data-urlencode 'query=probe_success{job="probe/apollo-observability/blackbox-edge"}' http://prometheus:9090/api/v1/query)
    if python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; sys.exit(not r or any(x["value"][1]!=sys.argv[1] for x in r))' "$expected" <<< "$payload"; then return; fi
    sleep 3
  done
  echo "Edge probe never reached $expected" >&2; return 1
}
probe 1
kubectl -n apollo-airlines-ui get httproute frontend -o yaml > "$work/route.yaml"
route_saved=true
kubectl -n apollo-airlines-ui delete httproute frontend >/dev/null
probe 0
kubectl apply -f "$work/route.yaml" >/dev/null
probe 1
route_saved=false
# Synthetic rule isolates the delivery path from the longer booking SLO windows.
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: apollo-delivery-lab
  namespace: $ns
  labels: {app.kubernetes.io/part-of: apollo-airlines}
spec:
  groups:
    - name: delivery-lab
      interval: 5s
      rules:
        - alert: ApolloDeliveryLab
          expr: vector(1)
          labels: {run: "$pod"}
EOF
notification() {
  local state=$1 payload
  for _ in $(seq 1 60); do
    payload=$(client http://alert-receiver:8080/)
    if python3 -c 'import json,sys; events=json.load(sys.stdin); sys.exit(not any(a["status"]==sys.argv[1] and a["labels"].get("run")==sys.argv[2] for e in events for a in e.get("alerts",[])))' "$state" "$pod" <<< "$payload"; then return; fi
    sleep 3
  done
  echo "No $state delivery for this run" >&2; return 1
}
notification firing
kubectl -n "$ns" patch prometheusrule apollo-delivery-lab --type=json -p '[{"op":"replace","path":"/spec/groups/0/rules/0/expr","value":"vector(0) > 1"}]' >/dev/null
notification resolved
echo 'PASS: trusted edge probe failed/recovered; firing and resolved payloads delivered.'
