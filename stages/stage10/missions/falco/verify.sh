#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
trap 'kube exec apollo-marker -- rm -f /tmp/apollo-falco-marker >/dev/null' EXIT
kube exec apollo-marker -- sh -c 'echo harmless > /tmp/apollo-falco-marker'
found=false
for _ in $(seq 1 30); do
  if kube -n falco logs -l app.kubernetes.io/name=falco -c falco --since-time="$started" --tail=-1 | grep -Eq '"rule"[[:space:]]*:[[:space:]]*"Apollo harmless marker"'; then
    found=true; break
  fi
  sleep 2
done
[[ "$found" == true ]] || { echo 'No matching runtime event; inspect Falco startup, driver and rule logs.' >&2; exit 1; }
kube exec apollo-marker -- cat /tmp/apollo-falco-marker
kube exec apollo-marker -- rm /tmp/apollo-falco-marker
kube exec apollo-marker -- test ! -e /tmp/apollo-falco-marker
echo 'PASS: harmless action succeeded, Falco detected it, marker removed.'
