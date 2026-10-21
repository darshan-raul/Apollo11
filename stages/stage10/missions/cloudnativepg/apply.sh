#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
if kind get clusters | grep -Fxq "$MISSION"; then
  echo 'Mission cluster already exists; inspect or teardown before restarting.' >&2; exit 2
fi
kind create cluster --name "$MISSION" --image kindest/node:v1.34.0 --config "$DIR/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 120s
helm --kube-context "kind-$MISSION" upgrade --install cnpg cloudnative-pg   --repo https://cloudnative-pg.github.io/charts --version 0.29.1   --namespace cnpg-system --create-namespace --wait --timeout 5m
kube apply -f "$DIR/cluster.yaml"
kube -n apollo-data-lab wait --for=condition=Ready cluster/booking-lab --timeout=600s
kube -n apollo-data-lab get cluster,pods,pvc
