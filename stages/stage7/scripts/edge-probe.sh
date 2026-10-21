#!/usr/bin/env bash
# Configure a trusted HTTPS probe through the actual Envoy LoadBalancer.
set -euo pipefail
source "$(dirname "$0")/context.sh"
apollo_context_guard
ns=apollo-observability
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
kubectl -n apollo-airlines-apps get secret apollo-edge-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "$work/ca.crt"
kubectl -n "$ns" create configmap blackbox-trust --from-file=ca.crt="$work/ca.crt" --dry-run=client -o yaml | kubectl apply -f -
ip=$(kubectl -n envoy-gateway-system get service -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
[[ -n "$ip" ]] || { echo 'Gateway has no LoadBalancer address' >&2; exit 1; }
kubectl -n "$ns" rollout restart deployment/blackbox
kubectl -n "$ns" rollout status deployment/blackbox --timeout=120s
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: blackbox-edge
  namespace: $ns
  labels:
    app.kubernetes.io/part-of: apollo-airlines
spec:
  interval: 15s
  module: https_apollo
  prober:
    url: blackbox.$ns.svc:9115
  targets:
    staticConfig:
      static: [https://$ip/healthz]
EOF
echo 'Query probe_success{job="probe/apollo-observability/blackbox-edge"}; require 1.'
