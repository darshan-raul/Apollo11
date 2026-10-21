# CloudNativePG: replicated booking data and recovery

Optional Stage 10 mission. Prerequisites: Stage 3 persistence, Stage 4 disruption,
Docker, kind, Helm, kubectl and Internet access. Budget roughly 3 GiB additional
free RAM and two 1 GiB database volumes; this is an estimate. Run separately
from a full Stage 7 deployment on constrained hosts.

This mission uses a disposable `apollo11-cloudnativepg` cluster and a private
kubeconfig. It creates a small booking-evidence database, not a migration of the
running Apollo booking service. The operator manages two PostgreSQL instances
on two workers. Chart 0.29.1 is pinned; PostgreSQL uses 17.5. Existing Stage 10
legacy manifests are not inputs to this mission.

## Build

Run from this directory:

```bash
bash apply.sh
export KUBECONFIG="$PWD/.kubeconfig"
kubectl -n apollo-data-lab get cluster booking-lab -o yaml
kubectl -n apollo-data-lab get pods -o wide
kubectl -n apollo-data-lab get services,pvc
```

Identify `status.currentPrimary`, the replica, and the read-write Service.
Explain why two running database Pods alone do not prove replication.

## Inspect, break, recover

Read `verify.sh`, then run it and retain the output:

```bash
bash verify.sh | tee verification.log
```

It reads a seeded booking-evidence row, saves a logical dump to `backup.sql`,
deletes the current primary, waits for a *different* primary to accept SQL,
and checks the row survived. It reports observed recovery time. Then it restores
the dump into a separate database, reads the same row there, and removes only
that temporary restore database. The source survives this exercise.

For manual inspection before the break:

```bash
primary=$(kubectl -n apollo-data-lab get cluster booking-lab -o jsonpath='{.status.currentPrimary}')
kubectl -n apollo-data-lab exec "$primary" -- psql -U postgres -d booking -c 'TABLE booking_evidence'
kubectl -n apollo-data-lab exec "$primary" -- psql -U postgres -c 'SELECT application_name,state,sync_state FROM pg_stat_replication'
```

If the verifier fails, inspect Cluster conditions, events and instance logs.
Keep `backup.sql`; do not delete PVCs to make the operator appear healthy.
Allow reconciliation, require a writable primary, and rerun the verifier.
The dump has teaching data only; real dumps need access controls and retention.

This is **logical backup/restore**, not WAL archiving, point-in-time recovery or
proof of zero data loss. Default asynchronous replication can lose recent writes.
Deleting a Pod is not a regional failure. Stage 9's Velero exercise remains a
separate requirement; physical backup/PITR is an advanced extension.

## Explain and clean up

Why did the writable endpoint survive a primary identity change? Which writes
could asynchronous failover lose? Why restore into a separate database? What
would be needed to measure an RPO rather than checking one retained row?

```bash
bash teardown.sh
kind get clusters
```

Require `apollo11-cloudnativepg` to be absent. Cluster deletion removes its local
volumes and operator CRDs. Keep or explicitly delete your local `backup.sql`
and verification log after reviewing the evidence.

[CloudNativePG quickstart](https://cloudnative-pg.io/docs/current/quickstart/)
explains the controller and Cluster resource;
[backup documentation](https://cloudnative-pg.io/docs/current/backup/) covers the
physical-backup capabilities beyond this logical-dump lab.
