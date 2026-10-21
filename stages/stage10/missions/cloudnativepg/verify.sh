#!/usr/bin/env bash
# Disrupt only this mission's database; prove row survival and logical restore.
source "$(dirname "$0")/common.sh"
primary() { kube -n apollo-data-lab get cluster booking-lab -o jsonpath='{.status.currentPrimary}'; }
sql() { kube -n apollo-data-lab exec "$(primary)" -- psql -U postgres -d booking -v ON_ERROR_STOP=1 -Atc "$1"; }
[[ "$(sql "SELECT passenger FROM booking_evidence WHERE reference='APOLLO-001'")" == mission-passenger ]]
kube -n apollo-data-lab exec "$(primary)" -- pg_dump -U postgres -d booking --clean --if-exists --no-owner > "$DIR/backup.sql"
[[ -s "$DIR/backup.sql" ]]
old=$(primary)
start=$SECONDS
kube -n apollo-data-lab delete pod "$old" --wait=true
# A replacement alone is insufficient: require a different elected primary.
for _ in $(seq 1 120); do
  new=$(primary)
  if [[ -n "$new" && "$new" != "$old" ]] && sql 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 2
done
[[ "$(primary)" != "$old" ]] || { echo 'No failover observed' >&2; exit 1; }
[[ "$(sql "SELECT passenger FROM booking_evidence WHERE reference='APOLLO-001'")" == mission-passenger ]]
echo "Failover and row survival proved in $((SECONDS-start))s"
# Restore into a separate database; the surviving source remains intact.
sql 'DROP DATABASE IF EXISTS booking_restore'
sql 'CREATE DATABASE booking_restore'
kube -n apollo-data-lab exec -i "$(primary)" -- psql -U postgres -d booking_restore -v ON_ERROR_STOP=1 < "$DIR/backup.sql"
restored=$(kube -n apollo-data-lab exec "$(primary)" -- psql -U postgres -d booking_restore -Atc "SELECT passenger FROM booking_evidence WHERE reference='APOLLO-001'")
[[ "$restored" == mission-passenger ]]
sql 'DROP DATABASE booking_restore'
kube -n apollo-data-lab wait --for=condition=Ready cluster/booking-lab --timeout=300s
echo 'PASS: replicated row survived primary loss; logical backup restored separately.'
