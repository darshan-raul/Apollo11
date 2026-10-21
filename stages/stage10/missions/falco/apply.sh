#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
[[ "$(uname -s)" == Linux ]] || { echo 'This mission requires a Linux Docker host with modern eBPF support.' >&2; exit 2; }
if kind get clusters | grep -Fxq "$MISSION"; then
  echo 'Mission cluster already exists; inspect or teardown before restarting.' >&2; exit 2
fi
kind create cluster --name "$MISSION" --image kindest/node:v1.34.0 --config "$DIR/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 120s
helm --kube-context "kind-$MISSION" upgrade --install falco falco   --repo https://falcosecurity.github.io/charts --version 9.2.1   --namespace falco --create-namespace -f "$DIR/values.yaml" --wait --timeout 5m
kube run apollo-marker --image=busybox:1.37.0 --restart=Never --command -- sleep 3600
kube wait --for=condition=Ready pod/apollo-marker --timeout=120s
