#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
kind delete cluster --name "$MISSION"
if kind get clusters | grep -Fxq "$MISSION"; then
  echo 'Mission cluster still exists' >&2; exit 1
fi
rm -f "$KUBECONFIG" "$DIR/backup.sql"
echo 'Owned cluster, volumes, controllers, private context and local dump removed.'
