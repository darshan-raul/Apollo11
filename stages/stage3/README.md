---
title: "Stage 3: Mission Data — Persistent Storage, StatefulSets"
description: "Replace emptyDir with PVCs, convert all 4 stateful workloads (3 PG + redis) to StatefulSets, move DB schema to init containers, and keep data seeding as one-shot jobs. The Envoy Gateway + MetalLB access stack from Stage 2 carries over unchanged."
---

# Stage 3: Mission Data

**Goal:** Give stateful workloads permanent storage that survives pod restarts.
Convert `identity-db`, `flight-db`, `booking-db`, and `redis` from `Deployment` +
`emptyDir` to **`StatefulSet` + `PersistentVolumeClaim`**, with stable per-pod
network identity, schema bootstrapping via init containers, and idempotent
data seeding via one-shot Jobs. The Stage 2 access stack (Envoy Gateway +
MetalLB) is unchanged.

| | |
|---|---|
| **New concept** | StatefulSet, VolumeClaimTemplate, Headless Service (`clusterIP: None`), Init container schema bootstrap, PVC lifecycle, kind `local-path` StorageClass |
| **Workloads changed** | 4 (3 PostgreSQL + redis) |
| **Workloads unchanged** | 6 (all app Deployments, frontend, gateway, MetalLB) |
| **Code changes** | None (app code doesn't know or care about Deployment vs StatefulSet) |
| **Verify target** | **53/53 checks pass** |

---

## Lessons learned during build (read this if you're changing this stage)

Three real bugs were found and fixed during end-to-end testing on a
fresh kind cluster. Keep them in mind if you modify the StatefulSets:

1. **Don't use a separate init container that runs `psql` against
   `127.0.0.1` after `pg_isready` — it deadlocks.** The kubelet gates
   the main container on the init container's success, so the init's
   `pg_isready` against `127.0.0.1` waits for the main container, but
   the main container can't start until init exits. **Fix:** mount the
   init SQL ConfigMap at `/docker-entrypoint-initdb.d/` inside the
   Postgres container and set `PGDATA=/var/lib/postgresql/data/pgdata`.
   The official Postgres entrypoint runs the SQL during `initdb` on
   first start and skips it on every subsequent restart.

2. **Postgres 15.18's `psql` rejects `TIME f.dep_time` with
   "syntax error at or near f".** Use explicit `f.dep_time::time`
   casts. The same SQL ran fine on `psql` 13; on 15 the type coercion
   rule is stricter.

3. **`flight_number UNIQUE` is wrong** when the same flight flies
   daily. Use `UNIQUE (flight_number, departure_time)` so the seed can
   insert 31 rows for each flight number across the next 31 days.

4. **`nslookup` isn't in the `python:3.12-slim` image** (the identity
   service). The verify script uses `getent hosts` instead — it works
   in any minimal image and resolves headless services to pod IPs.

5. **The teardown order matters.** Deleting `envoy-gateway-install.yaml`
   while app namespaces are still around causes the apiservice
   deletion to hang on webhooks. Teardown deletes the app namespaces
   first, then the Gateway/HTTPRoutes, then Envoy, then MetalLB.

---

## Why this matters

In Stages 1 and 2, all databases used `emptyDir`:

```
emptyDir     ←─ stages 1/2
Pod deleted  →  data GONE  (emptyDir lives in node's RAM/disk, dies with pod)
Pod restarted → fresh empty volume
```

`emptyDir` is fine for **cache** (and even then, only if losing it is OK).
It's terrible for **data**. Stage 3 switches to `PersistentVolumeClaim`:

```
PVC (1Gi, ReadWriteOnce)
  ↓
PV (provisioned by StorageClass — survives pod death)
  ↓
Pod restarted → same PVC re-attached → data intact
```

After Stage 3 you can `kubectl delete pod identity-db-0` and the new pod
will come back with the same data. Try it:

```bash
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c 'SELECT count(*) FROM users;'   # 2

kubectl delete pod -n apollo-airlines-apps identity-db-0
# wait ~10s
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c 'SELECT count(*) FROM users;'   # still 2
```

---

## What's new vs Stage 2 set 4

| Area | Stage 2 | Stage 3 |
|---|---|---|
| **Stateful workloads** | `Deployment` + `emptyDir` (4) | `StatefulSet` + `1Gi PVC` (4) |
| **DB schema** | One-shot `init-*.yaml` Job | Init container inside the StatefulSet pod |
| **DB data** | Combined with schema in the same Job | Idempotent `seed-*.yaml` Job (runs once) |
| **Network identity** | Deployment pods have random names | Stable ordinals: `identity-db-0.apollo-airlines-apps` |
| **App Deployments** | Unchanged | Unchanged (still connect via `identity-db`, `flight-db`, etc.) |
| **Envoy Gateway + MetalLB** | Set 4 access stack | **Carried over verbatim** — persists for all later stages |
| **Namespaces** | 2 (apps, ui) | 2 (apps, ui) |
| **ServiceAccounts / NetworkPolicies** | 13 / 16 (reference) | 13 / 16 (reference, unchanged) |
| **Code (`stages/stage3/code/`)** | Snapshot of stage 2 code | Snapshot of stage 2 code (no edits) |

---

## File layout

```
stages/stage3/
├── README.md                          # this file
├── code/                              # snapshot of stages/stage2/code/  (no changes)
└── k8s/
    ├── config/                        # 2 namespaces, configmap, secrets (verbatim from set 4)
    ├── serviceaccounts/accounts.yaml  # 13 SAs (verbatim from set 4)
    ├── networkpolicies/               # 16 manifests (reference only, unchanged)
    ├── apps/
    │   ├── identity-db/               # NEW: sts + svc + headless + init-script (entrypoint hook, not init container)
    │   ├── flight-db/                 # NEW: same shape (UNIQUE (flight_number, departure_time))
    │   ├── booking-db/                # NEW: same shape
    │   ├── redis/                     # NEW: sts + svc + headless (no schema)
    │   ├── identity/                  # unchanged Deployment + Service
    │   ├── flight/                    # unchanged
    │   ├── booking/                   # unchanged
    │   ├── search/                    # unchanged
    │   ├── notification/              # unchanged
    │   └── frontend/                  # unchanged
    ├── jobs/                          # NEW: 3 seed-* Jobs + 3 seed ConfigMaps
    ├── gateway/                       # unchanged (Envoy Gateway + HTTPRoutes)
    └── metallb/                       # unchanged
```

---

## StatefulSet vs Deployment — what's different

| | Deployment | StatefulSet |
|---|---|---|
| Pod name | `app-xxxxx-yyyyy` (random) | `app-0`, `app-1` (ordinal, stable) |
| Pod identity across restarts | None | Stable: `app-0` always gets the same PVC |
| Scaling | All replicas in parallel | Ordered: pod N+1 starts after pod N is Ready |
| Storage | Shared or none | `VolumeClaimTemplate` → per-pod PVC |
| Service | `ClusterIP` (`type: ClusterIP`) | `Headless` (`clusterIP: None`) |
| Use when | Stateless, interchangeable replicas | Stateful, per-pod identity matters |

For Apollo Airlines, each DB has `replicas: 1`, so the "ordered scaling"
guarantee doesn't matter much. **What matters is stable identity + per-pod
PVCs** — when the pod restarts, the new pod comes back with the same
storage attached.

---

## Headless Service — why each StatefulSet needs one

A regular `Service` has a virtual IP that load-balances across pods. A
**headless** service has `clusterIP: None` — CoreDNS returns the pod IPs
directly, and each pod gets a stable DNS name:

```
identity-db-headless.apollo-airlines-apps.svc.cluster.local
identity-db-0.identity-db-headless.apollo-airlines-apps.svc.cluster.local  →  10.244.1.5
identity-db-1.identity-db-headless.apollo-airlines-apps.svc.cluster.local  →  10.244.2.7
```

The StatefulSet `serviceName: identity-db-headless` field tells the
controller: "wire my pods to this service for DNS."

**App code doesn't use the headless service.** App pods connect to the
regular `identity-db` Service (the same one Stage 2 used) — that service
load-balances to the single StatefulSet pod. The headless service is
mostly for direct pod-to-pod communication (replication clients like
`repmgr`, or operators that need to address specific replicas). In our
case it's the prerequisite for the StatefulSet, even if we don't
directly resolve it from app code.

---

## Init Container pattern for schema

> **Implementation note (Stage 3 build log):** the original plan was a
> separate `initContainers[]` entry that runs `psql -f /init/init.sql`
> against `127.0.0.1` after `pg_isready`. **That deadlocks** — the
> kubelet gates the main container on the init container's success, so
> the init container's `pg_isready` against `127.0.0.1` waits for the
> main container, but the main container can't start because the init
> hasn't exited. (We discovered this on the first real run — the
> `statefulset/identity-db` rolled out 0/1 indefinitely.)
>
> **Fix:** use the official Postgres image's built-in
> `/docker-entrypoint-initdb.d/` mechanism instead. Mount the init SQL
> ConfigMap there. On first start (empty data dir), the entrypoint runs
> the SQL during `initdb`. On every subsequent restart, the data dir is
> populated and the entrypoint skips `/docker-entrypoint-initdb.d/`
> entirely — the SQL is not re-run, which is exactly what we want.
>
> The intent of the README is unchanged: schema re-applies on first
> start, persists across pod restarts, and re-applies if you delete the
> PVC and start fresh. The mechanism is just the Postgres image's
> standard one, not a custom init container.

The init SQL is mounted via a ConfigMap volume:

```yaml
containers:
  - name: postgres
    image: postgres:15-alpine
    env:
      - { name: PGDATA, value: /var/lib/postgresql/data/pgdata }
    volumeMounts:
      - { name: pg-data,     mountPath: /var/lib/postgresql/data }
      - { name: init-script, mountPath: /docker-entrypoint-initdb.d }
volumes:
  - name: init-script
    configMap:
      name: identity-db-init-script
volumeClaimTemplates:
  - metadata: { name: pg-data }
    spec:
      accessModes: ["ReadWriteOnce"]
      resources: { requests: { storage: 1Gi } }
```

**Why `PGDATA=/var/lib/postgresql/data/pgdata`?** The Postgres entrypoint
checks if the `PGDATA` directory is non-empty. If it is, the entrypoint
skips `initdb` (and the `/docker-entrypoint-initdb.d/*.sql` scripts).
Naming `PGDATA` to a subdirectory (`pgdata`) means: when we mount an
**empty** PVC at `/var/lib/postgresql/data`, the entrypoint creates
`pgdata/` inside it on first start, runs `initdb` there, and runs the
SQL. On every subsequent restart, `pgdata/` exists and is non-empty, so
the entrypoint skips both `initdb` and the init SQL — exactly the
idempotent behaviour we want.

**Why not keep the schema in a Job?** Two reasons:
1. The entrypoint runs the SQL **on first start of the pod** on
   whatever node it lands on. A Job runs once per cluster creation. If
   you `kubectl delete pod identity-db-0` and the new pod lands on a
   fresh node with an empty PVC, the entrypoint re-applies the schema
   (`CREATE TABLE IF NOT EXISTS` is safe to re-run).
2. No coordination needed. The Job model requires a script that waits
   for the DB to be ready, then runs SQL. The entrypoint hook is built
   into the pod lifecycle.

The seed (data) is still a Job — you don't want to re-insert 186 flight
rows every time the pod restarts. The seed is `ON CONFLICT DO NOTHING`
(for tables with unique constraints; for `flights` we drop the conflict
clause since each `flight_number` flies daily and there's no composite
unique constraint to match against).

---

## StorageClass — the bit everyone skips

A `PersistentVolumeClaim` is a **request** for storage. Kubernetes
satisfies that request by binding it to a `PersistentVolume` (PV) that
matches its size, access mode, and (if specified) `storageClassName`.

A `StorageClass` describes **how** to provision a PV:
- `local-path` (default in kind) — provisions a `hostPath` PV on the node
  the pod lands on. Fast, but the data is **node-local** — if the pod
  reschedules to a different node, the data is gone (unless the
  `local-path` provisioner is configured for `WaitForFirstConsumer`
  binding mode, which it isn't in stock kind).
- `standard` (GCE), `gp2`/`gp3` (AWS), `pd-standard` (GCP) — cloud
  network-attached storage. Survives node failure.
- For real production, use a CSI driver (AWS EBS, GCE PD, Rook/Ceph,
  Longhorn, etc.).

**This Stage's PVCs omit `storageClassName`** — they use the cluster
default, which kind sets to `local-path`. That works for our dev
cluster because pods are rescheduled within the same node pool
(two workers; StatefulSets with `replicas: 1` tend to land on the same
node on each rollout).

To inspect the storage class in your cluster:

```bash
kubectl get storageclass
# NAME                 PROVISIONER                    RECLAIMPOLICY   ...
# local-path (default) rancher.io/local-path          Delete          ...

kubectl get pvc -n apollo-airlines-apps
# NAME                       STATUS   VOLUME                                     CAPACITY   ...
# pg-data-identity-db-0      Bound    pvc-0a1b2c3d-...                          1Gi        ...
# pg-data-flight-db-0        Bound    pvc-1b2c3d4e-...                          1Gi        ...
# pg-data-booking-db-0       Bound    pvc-2c3d4e5f-...                          1Gi        ...
# redis-data-redis-0         Bound    pvc-3d4e5f6a-...                          1Gi        ...
```

If you want to pin to a specific StorageClass explicitly:

```yaml
volumeClaimTemplates:
  - metadata: { name: pg-data }
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-path   # <-- explicit
      resources: { requests: { storage: 1Gi } }
```

---

## Architecture

```
        Browser
          |
          |  HTTP, Host: <svc>.apollo.local
          v
   172.18.0.50  (MetalLB-assigned, persisted from Stage 2)
          |
          v
   +-----------+         +-----------+
   |  Envoy    |  routes |  Envoy    |  ← unchanged
   |  Service  |-------->|  proxy    |
   |  (LB)     |         +-----------+
   +-----------+               |
                                v
       +----------+ +----------+ +----------+ +----------+ +----------+
       | identity | | flight   | | booking  | | search   | | notif.   |
       +----------+ +----------+ +----------+ +----------+ +----------+
              |           |            |            |             |
              v           v            v            v             v
       ┌──────────────────────────────────────────────────────────────┐
       │ StatefulSets (1 replica each)                                │
       │                                                              │
       │  identity-db  ── pg-data-identity-db-0  (1Gi PVC, Bound)   │
       │  flight-db    ── pg-data-flight-db-0    (1Gi PVC, Bound)   │
       │  booking-db   ── pg-data-booking-db-0   (1Gi PVC, Bound)   │
       │  redis        ── redis-data-redis-0     (1Gi PVC, Bound)   │
       │                                                              │
       │  Init container in each DB pod:                              │
       │    1. Wait for pg_isready                                    │
       │    2. Run init.sql (idempotent CREATE TABLE IF NOT EXISTS)   │
       │    3. Exit → main container starts                           │
       └──────────────────────────────────────────────────────────────┘
                          |
                          v
                  ┌──────────────────┐
                  │  seed-* Jobs     │  ← one-shot, ON CONFLICT DO NOTHING
                  │  (3 jobs)        │
                  └──────────────────┘
```

---

## Apply

```bash
cd stages/stage3
./scripts/apply.sh
```

`apply.sh` runs 10 steps:
1. **Build images** — frontend + 5 backend services
2. **Namespaces + config + secrets**
3. **ServiceAccounts** (13)
4. **Apps** — 4 StatefulSets + 6 Deployments + 4 headless SVCs + 4 ClusterIP SVCs
5. **Wait for StatefulSets** — `kubectl rollout status` for each
6. **Seed jobs** (3)
7. **Wait for seed jobs** to succeed
8. **MetalLB** install + IP pool + L2 advertisement
9. **Envoy Gateway** install + GatewayClass + Gateway + 6 HTTPRoutes
10. **Wait for MetalLB to assign a LoadBalancer IP**, then print `/etc/hosts` reminder

**Why does step 5 exist?** The init container inside each StatefulSet pod
runs the schema. We block until `kubectl rollout status` reports
`ready=1` before applying the seed Jobs. If the init container is still
running when the seed Job tries to connect, the seed will retry via its
`pg_isready` loop — but blocking upfront gives a clean linear log.

After the script prints the MetalLB IP, set up local DNS:

```bash
# Use the IP printed by apply.sh:
172.18.0.50  frontend.apollo.local identity.apollo.local flight.apollo.local \
              booking.apollo.local search.apollo.local
```

Or use nip.io to skip `/etc/hosts`:
```bash
curl -H 'Host: frontend.apollo.local' http://frontend.172-18-0-50.nip.io/
```

---

## Verify

```bash
./scripts/verify.sh
```

**Expected: 53/53 checks pass.** Coverage:

| Group | Checks |
|---|---|
| Namespaces | 4 (apps, ui, envoy-gateway-system, metallb-system) |
| StatefulSets | 4 (all 1/1 ready) |
| StatefulSet pods | 4 (all Ready) |
| PVCs | 4 (all Bound) |
| PVs | ≥ 4 Bound |
| Headless SVCs | 4 (all `clusterIP: None`) |
| Headless DNS | 4 (each headless name resolves to a pod IP) |
| ClusterIP SVCs | 4 (for app connections) |
| App Deployments | 6 (all ≥ 2/2 ready) |
| MetalLB controller | 1 |
| Envoy Gateway controller + proxy | 2 |
| Seed jobs | 3 (all succeeded) |
| IPAddressPool + Gateway Programmed | 2 |
| HTTPRoutes | 1 (count ≥ 6 with parents) |
| Smoke tests | 4 (identity, flight, frontend, login) |
| Seed data present | 3 (users, airports, flights row counts) |
| App→Redis DNS | 1 |

---

## Test the persistence

The point of Stage 3 is **durable data**. Prove it:

```bash
# 1. Note current data
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c 'SELECT count(*) FROM users;'
#  count
# -------
#      2

# 2. Kill the pod
kubectl delete pod -n apollo-airlines-apps identity-db-0
# pod "identity-db-0" deleted

# 3. StatefulSet recreates it (~5–10s)
kubectl get pod -n apollo-airlines-apps -w
# identity-db-0   0/1   ContainerCreating   ...
# identity-db-0   1/1   Running              ...   ← data still here

# 4. Data is intact
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c 'SELECT count(*) FROM users;'
#  count
# -------
#      2    ← same!

# 5. Create a new row, then delete the pod again — the new row survives
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c \
  "INSERT INTO users (email, password_hash) VALUES ('test@x.com', 'x');"
kubectl delete pod -n apollo-airlines-apps identity-db-0
sleep 10
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c "SELECT email FROM users WHERE email = 'test@x.com';"
#  email
# ----------
#  test@x.com
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Deletes the 4 PVCs (releases the local-path PVs), both namespaces, Envoy
Gateway, and MetalLB. Safe to re-run.

---

## Concepts you should be able to answer

1. Why does a StatefulSet require a Headless Service (`clusterIP: None`)?
2. What's the difference between `volumeClaimTemplates` and a normal
   `volumes:` entry?
3. Why does the init container use `127.0.0.1` for `pg_isready` instead
   of `identity-db`?
4. What would break if we kept the schema in a Job (Stage 2 style) and
   only added a PVC?
5. Why does Stage 3 still have Jobs at all (the seed jobs)?
6. What is a `StorageClass`? Why didn't we set `storageClassName` on
   the PVCs?
7. Where is the data physically stored (on the node)? What happens if
   the node is wiped?
8. Why did we make redis a StatefulSet in Stage 3 instead of waiting
   for Stage 7?

---

## What comes next (Stage 4)

`livenessProbe`, `readinessProbe`, `startupProbe`, `resources.requests`,
`resources.limits`, and `PodDisruptionBudget` for the frontend + booking
services. Probes give Kubernetes the signal to restart unhealthy pods
(whereas right now, a stuck Postgres pod will sit there forever).
