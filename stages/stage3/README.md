---
title: "Stage 3: Mission Data — Persistent Storage, StatefulSets"
description: "Replace emptyDir with PVCs, convert all 4 stateful workloads (3 PG + redis) to StatefulSets, move DB schema to the Postgres entrypoint hook (/docker-entrypoint-initdb.d/), keep data seeding as one-shot jobs, add scheduled pg_dump CronJob backups, and verify working app initContainers."
---

# Stage 3: Mission Data

**Goal:** Give stateful workloads permanent storage that survives pod restarts.
Convert `identity-db`, `flight-db`, `booking-db`, and `redis` from `Deployment` +
`emptyDir` to **`StatefulSet` + `PersistentVolumeClaim`**, with stable per-pod
network identity, schema bootstrapping through the official PostgreSQL
entrypoint hook, idempotent data seeding via one-shot Jobs, scheduled logical
backups via `CronJob`, and a working `initContainer` on `booking`. The Stage 2
access stack (Envoy Gateway + MetalLB) is unchanged.

| | |
|---|---|
| **New concept** | StatefulSet, VolumeClaimTemplate, Headless Service (`clusterIP: None`), Postgres entrypoint-hook schema bootstrap (`/docker-entrypoint-initdb.d/`), `CronJob`, working `initContainer`, local-path PV `nodeAffinity` pinning |
| **Workloads changed** | 4 StatefulSets (3 PostgreSQL + redis), `booking` (`initContainer`), `pg-backup` `CronJob` |
| **Workloads unchanged** | 5 app Deployments (`identity`, `flight`, `search`, `notification`, `frontend`), gateway, MetalLB |
| **Code changes** | None (app code doesn't know or care about Deployment vs StatefulSet) |
| **Verify target** | All checks pass (`0` failures) |

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

## What's new vs Stage 2 set 5

| Area | Stage 2 | Stage 3 |
|---|---|---|
| **Stateful workloads** | `Deployment` + `emptyDir` (4) | `StatefulSet` + `1Gi PVC` (4) |
| **DB schema** | One-shot `init-*.yaml` Job | Postgres `/docker-entrypoint-initdb.d/` hook |
| **DB data** | Combined with schema in the same Job | Idempotent `seed-*.yaml` Job (runs once) |
| **Network identity** | Deployment pods have random names | Stable ordinals: `identity-db-0.apollo-airlines-apps` |
| **App Deployments** | Unchanged | `booking` adds `wait-for-booking-db` `initContainer`; others unchanged |
| **Scheduled backups** | Manual only | `pg-backup` `CronJob` (`0 2 * * *`) + `pg-backups` 1Gi PVC |
| **Envoy Gateway + MetalLB** | Stage 2 set 5 access stack | **Carried over verbatim** — persists for all later stages |
| **Namespaces** | 2 (apps, ui) | 2 (apps, ui) |
| **ServiceAccounts** | 13 SAs (automount disabled) | 14 SAs (13 in `apollo-airlines-apps` incl. `pg-backup`, 1 in `apollo-airlines-ui`; automount disabled) |
| **NetworkPolicies** | Deferred to Stage 8 (Calico) | Deferred to Stage 8 (Calico) |
| **Code (`stages/stage3/code/`)** | Snapshot of stage 2 code | Snapshot of stage 2 code (shared contracts synced) |

---

## File layout

```
stages/stage3/
├── README.md                          # this file
├── code/                              # snapshot of stages/stage2/code/  (no changes)
├── scripts/                           # apply.sh, verify.sh, verify-tls.sh, teardown.sh, build-images.sh, generate-certs.sh
└── k8s/
    ├── config/                        # 2 namespaces, configmap, secrets, 14 serviceaccounts (incl. pg-backup)
    ├── apps/
    │   ├── identity-db/               # NEW: sts + svc + headless + init-script (entrypoint hook, not init container)
    │   ├── flight-db/                 # NEW: same shape (UNIQUE (flight_number, departure_time))
    │   ├── booking-db/                # NEW: same shape
    │   ├── redis/                     # NEW: sts + svc + headless (no schema)
    │   ├── identity/                  # Deployment + Service
    │   ├── flight/                    # Deployment + Service
    │   ├── booking/                   # Deployment (with wait-for-booking-db initContainer) + Service
    │   ├── search/                    # Deployment + Service
    │   ├── notification/              # Deployment + Service
    │   └── frontend/                  # Deployment + Service
    ├── jobs/                          # 3 seed-* Jobs + 3 seed ConfigMaps + pg-backup CronJob & pg-backups PVC
    ├── gateway/                       # Envoy Gateway + EnvoyProxy + HTTPRoutes + ReferenceGrant
    └── metallb/                       # MetalLB L2 Pool + Advertisement
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

## Entrypoint Hook Pattern for Schema Bootstrap

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
rows every time the pod restarts. All seed statements use `ON CONFLICT DO NOTHING`
(`ON CONFLICT (id) DO NOTHING` on `users`, `ON CONFLICT (code) DO NOTHING` on
`airports`, and `ON CONFLICT (flight_number, departure_time) DO NOTHING` on
`flights`), so re-running a seed Job is safe and idempotent.

---

## Working `initContainer` vs. Same-Pod Deadlock

Not all `initContainers` deadlock—only **self-referential** ones where an init
container waits for the main container in the **same** Pod:

| Pattern | Example | Why it succeeds or deadlocks |
|---|---|---|
| **Same-Pod self-wait (Deadlock)** | `identity-db` init running `pg_isready -h 127.0.0.1` | Kubelet blocks main `containers[]` until every `initContainer` exits `0`. The init waits for Postgres on `127.0.0.1`, while Postgres cannot start until init exits (`Init:0/1` forever). |
| **External dependency wait (Works)** | `booking` `wait-for-booking-db` running `pg_isready -h booking-db -p 5432` | `booking-db` runs in a **separate Pod** (`booking-db-0`). It starts and becomes Ready independently, `pg_isready` exits `0`, and kubelet then starts the main `booking` container. |

In `stages/stage3/k8s/apps/booking/booking-dep.yaml`, `booking` uses a working
`initContainer` to wait for `booking-db` before starting the Go server:

```yaml
initContainers:
  - name: wait-for-booking-db
    image: postgres:15-alpine
    command:
      - sh
      - -c
      - |
        until pg_isready -h booking-db -p 5432 -U postgres; do
          echo "Waiting for booking-db:5432..."
          sleep 2
        done
```

Inspect its completion status on running `booking` Pods:

```bash
kubectl get pods -n apollo-airlines-apps -l app=booking \
  -o jsonpath='{range .items[*]}{.metadata.name}{" init="}{.status.initContainerStatuses[0].name}{" ready="}{.status.initContainerStatuses[0].ready}{" exit="}{.status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}{end}'
```

---

## StorageClass — the bit everyone skips

A `PersistentVolumeClaim` is a **request** for storage. Kubernetes
satisfies that request by binding it to a `PersistentVolume` (PV) that
matches its size, access mode, and (if specified) `storageClassName`.

A `StorageClass` describes **how** to provision a PV:
- `standard` (`rancher.io/local-path`, default in kind) — uses
  `WaitForFirstConsumer` binding and provisions a node-local `hostPath` PV on
  the worker node where the Pod first schedules. The resulting PV carries a
  `nodeAffinity` rule pinning future restarts of `identity-db-0` back to that
  same node. Data survives Pod deletion, but because storage is node-local:
  - if that worker node becomes unavailable, the Pod stays `Pending`; and
  - if the PVC is deleted (`ReclaimPolicy: Delete`) or the node's local-path
    directory is wiped, the data is lost.
- `gp2`/`gp3` (AWS EBS), `pd-standard`/`pd-balanced` (GCP PD) — cloud
  network-attached storage that can re-attach across nodes within a zone.
- For real production, use a CSI driver (AWS EBS, GCE PD, Rook/Ceph,
  Longhorn, etc.).

**This Stage's PVCs omit `storageClassName`** — they use the cluster
default, which kind names `standard`. Because `WaitForFirstConsumer` is active,
the PVC remains `Pending` until the StatefulSet Pod is scheduled onto a worker,
and then binds to a PV pinned to that node.

To inspect the storage class and PVs in your cluster:

```bash
kubectl get storageclass
# NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  ...

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
      storageClassName: standard   # <-- explicit
      resources: { requests: { storage: 1Gi } }
```

---

## Architecture

```
        Browser
          |
          |  HTTP (80) / HTTPS (443), Host: <svc>.apollo.local
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
        │  Schema bootstrap (Postgres pods only):                      │
        │    Mounts init.sql at /docker-entrypoint-initdb.d/. The      │
        │    Postgres entrypoint runs it during initdb on FIRST start   │
        │    (data dir empty). Skips it on every subsequent restart    │
        │    (data dir non-empty). Idempotent — CREATE TABLE IF NOT    │
        │    EXISTS.                                                  │
        └──────────────────────────────────────────────────────────────┘
                           |
                           v
                   ┌──────────────────┐
                   │  seed-* Jobs     │  ← one-shot, ON CONFLICT DO NOTHING
                   │  (3 jobs)        │
                   └──────────────────┘
```

---

## Author Before Bootstrap (`learner-work/stage3/`)

Before running `./scripts/apply.sh` for the full fleet, complete the scoped
conversion exercise in [`../../learner-work/stage3/`](../../learner-work/stage3/README.md):

1. Copy `learner-work/stage3/starter/` (`booking-db` `Deployment` + `emptyDir` +
   ClusterIP `Service`) into `learner-work/stage3/work/`.
2. Convert `booking-db` into a `StatefulSet` (`serviceName: booking-db-headless`,
   `PGDATA=/var/lib/postgresql/data/pgdata`, `/docker-entrypoint-initdb.d`
   mount, `ReadWriteOnce` `volumeClaimTemplates`) plus a headless `Service`
   (`clusterIP: None`).
3. Validate your manifests before bootstrapping:

```bash
bash learner-work/stage3/check.sh
```

---

## Apply

```bash
cd stages/stage3
./scripts/apply.sh
```

`apply.sh` runs 7 deployment steps (after image build and cluster preflight):
1. **Namespaces, config, secrets & ServiceAccounts** (14 SAs, including `pg-backup`)
2. **Stateful workloads & wait** — 4 StatefulSets + Headless/ClusterIP Services + schema ConfigMaps; waits for `rollout status` and `Ready`
3. **Database seed Jobs & backup CronJob** — applies and waits for `seed-identity-db`, `seed-flight-db`, `seed-booking-db`, and creates `CronJob/pg-backup` + `PVC/pg-backups`
4. **Application Deployments** — 6 Deployments (including `booking`'s `wait-for-booking-db` `initContainer`) + ClusterIP Services; waits for `rollout status`
5. **MetalLB** — native install + IP pool + L2 advertisement
6. **Envoy Gateway** — controller + CRDs install
7. **Gateway API resources & IP** — GatewayClass, EnvoyProxy, TLS Secret (`generate-certs.sh`), Gateway, ReferenceGrant, 6 HTTPRoutes, then waits for MetalLB LoadBalancer IP

**Why does step 2 wait before step 3?** The Postgres entrypoint runs the schema
during `initdb` on first start (empty data dir). The pod's readiness
probe (a `pg_isready` exec check) only passes once initdb has finished
and Postgres is accepting connections. Blocking on
`kubectl rollout status` and `kubectl wait --for=condition=Ready` guarantees
the seed Jobs in step 3 connect to a fully-initialized DB, and the app
Deployments in step 4 start against seeded databases.

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

**Expected: All checks pass (`0` failures).** Coverage:

| Group | Description |
|---|---|
| Core Namespaces | `apollo-airlines-apps`, `apollo-airlines-ui`, `envoy-gateway-system`, `metallb-system` |
| ServiceAccounts | Token automount disabled on all 14 identities (including `pg-backup`) |
| StatefulSets & Pods | 4 StatefulSets (1/1 ready) + 4 pods Ready |
| Storage, PVCs & `nodeAffinity` | 4 StatefulSet PVCs (1Gi, Bound, ReadWriteOnce) + Bound PersistentVolumes with `PV.spec.nodeAffinity` |
| Headless Services & DNS | 4 headless services (`clusterIP: None`) + CoreDNS resolving to direct pod IPs |
| App Deployments & Seed Jobs | 6 Deployments (2/2 ready) + 3 seed jobs completed |
| Database Seed Integrity | Seed row counts (2 users, 6 airports, 186 flights across 31 days) |
| Envoy Gateway & MetalLB | GatewayClass, Gateway, 6 HTTPRoutes, MetalLB IP, and HTTP 200 checks |
| Flagship Workflow & Survival | Passenger auth, flight search, booking creation, Postgres & Redis AOF survival |
| Working `initContainer` | `booking` `wait-for-booking-db` spec & Pod `initContainerStatuses` (`ready=true`, `exitCode=0`) |
| Scheduled Backup `CronJob` | `pg-backup` `CronJob`, manual `--from=cronjob/pg-backup` Job completion, `pg-backups` PVC `Bound`, and `.sql.gz` dumps |
| PV Node-Pinning Proof | `identity-db-0` pinned node match + multi-worker `cordon` → `Pending` → `uncordon` recovery |
| Trusted HTTPS Workflow | TLS certificate verification, hostname rejection, and full HTTPS booking flow (`verify-tls.sh`) |

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
kubectl wait --for=condition=Ready pod/identity-db-0 -n apollo-airlines-apps --timeout=60s
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c "SELECT email FROM users WHERE email = 'test@x.com';"
#  email
# ----------
#  test@x.com
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -c "DELETE FROM users WHERE email = 'test@x.com';"
```

### Redis AOF persistence

`redis-0` runs with `--appendonly yes --appendfsync everysec` backed by its own `redis-data-redis-0` PVC. Prove a key survives Pod replacement:

```bash
kubectl exec -n apollo-airlines-apps redis-0 -- redis-cli SET lab:persist ok
sleep 2
kubectl delete pod -n apollo-airlines-apps redis-0
kubectl wait --for=condition=Ready pod/redis-0 -n apollo-airlines-apps --timeout=60s
kubectl exec -n apollo-airlines-apps redis-0 -- redis-cli GET lab:persist
# "ok"
kubectl exec -n apollo-airlines-apps redis-0 -- redis-cli DEL lab:persist
```

### PVC deletion data-loss boundary & recovery

Pod deletion preserves the PVC, whereas **PVC deletion destroys the underlying `Delete`-policy PV** and forces an empty schema bootstrap on the next start:

```bash
kubectl scale statefulset/flight-db -n apollo-airlines-apps --replicas=0
kubectl delete pvc pg-data-flight-db-0 -n apollo-airlines-apps
kubectl scale statefulset/flight-db -n apollo-airlines-apps --replicas=1
kubectl wait --for=condition=Ready pod/flight-db-0 -n apollo-airlines-apps --timeout=60s

# Entrypoint hook recreated the tables, but seeded rows are gone (0):
kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc 'SELECT count(*) FROM flights;'

# Recover by re-running the idempotent seed Job:
kubectl delete job seed-flight-db -n apollo-airlines-apps
kubectl apply -f stages/stage3/k8s/jobs/seed-flight-db.yaml
kubectl wait --for=condition=Complete job/seed-flight-db -n apollo-airlines-apps --timeout=60s
kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc 'SELECT count(*) FROM flights;'
# 186
```

### Logical backup & restore (`pg_dump`)

Prove you can take a logical backup and restore it into a separate database before cleaning up:

```bash
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  pg_dump -U postgres -d identity > /tmp/identity-backup.sql
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d postgres -c 'CREATE DATABASE identity_restore_test;'
kubectl exec -i -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity_restore_test < /tmp/identity-backup.sql
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity_restore_test -tAc 'SELECT count(*) FROM users;'
# 2
kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d postgres -c 'DROP DATABASE identity_restore_test;'
rm -f /tmp/identity-backup.sql
```

### Scheduled logical backups (`CronJob` `pg-backup`)

`stages/stage3/k8s/jobs/pg-backup-cronjob.yaml` provisions a dedicated `1Gi`
`pg-backups` PVC and a daily `CronJob` (`pg-backup`, `schedule: "0 2 * * *"`,
`concurrencyPolicy: Forbid`, `serviceAccountName: pg-backup`,
`restartPolicy: OnFailure`) that runs `pg_dump` + `gzip` across `identity-db`,
`flight-db`, and `booking-db` while pruning backups older than `7` days or
keeping the last `5` per database.

Because `standard` uses `WaitForFirstConsumer`, `pvc/pg-backups` stays `Pending`
after `apply.sh` until the first backup Job Pod schedules. Trigger a one-off
backup Job immediately and verify the `.sql.gz` dumps and `Bound` PVC:

```bash
kubectl get cronjob pg-backup -n apollo-airlines-apps
kubectl create job --from=cronjob/pg-backup pg-backup-manual -n apollo-airlines-apps
kubectl wait --for=condition=Complete job/pg-backup-manual -n apollo-airlines-apps --timeout=120s

# pg-backups transitions from Pending to Bound once the Job Pod schedules:
kubectl get pvc pg-backups -n apollo-airlines-apps
kubectl logs job/pg-backup-manual -n apollo-airlines-apps

# Clean up the manual Job (CronJob and pg-backups PVC remain intact):
kubectl delete job pg-backup-manual -n apollo-airlines-apps
```

### Local-path PV node pinning (`cordon` → `Pending` → `uncordon`)

Because kind's `standard` (`rancher.io/local-path`) StorageClass provisions
node-local storage, each bound PV carries `spec.nodeAffinity` pinning the
StatefulSet Pod back to the worker node that holds its directory. Prove that
Kubernetes refuses to reschedule `identity-db-0` onto another worker when its
pinned node is cordoned:

```bash
# 1. Inspect PV.spec.nodeAffinity and the node running identity-db-0
PV=$(kubectl get pvc pg-data-identity-db-0 -n apollo-airlines-apps -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV" -o jsonpath='{.spec.nodeAffinity}'; echo
NODE=$(kubectl get pod identity-db-0 -n apollo-airlines-apps -o jsonpath='{.spec.nodeName}')
echo "Pinned node: $NODE"

# 2. Cordon the pinned node and delete identity-db-0
kubectl cordon "$NODE"
kubectl delete pod identity-db-0 -n apollo-airlines-apps

# 3. Observe Pending / Unschedulable (other workers don't match PV.spec.nodeAffinity)
kubectl get pod identity-db-0 -n apollo-airlines-apps
kubectl describe pod identity-db-0 -n apollo-airlines-apps | tail -n 15

# 4. Uncordon the node and watch identity-db-0 return Ready on the same pinned node
kubectl uncordon "$NODE"
kubectl wait --for=condition=Ready pod/identity-db-0 -n apollo-airlines-apps --timeout=60s
kubectl get pod identity-db-0 -n apollo-airlines-apps -o wide
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Deletes the PVCs (4 StatefulSet PVCs plus `pg-backups`, releasing the local-path PVs), both namespaces, Envoy Gateway, and MetalLB. Safe to re-run.

---

## Explain

1. Why does a StatefulSet require a Headless Service (`clusterIP: None`)?
2. What's the difference between `volumeClaimTemplates` and a normal
   `volumes:` entry?
3. Why is the DB schema mounted at `/docker-entrypoint-initdb.d/` instead
   of running in a same-Pod `initContainer`, whereas `booking`'s
   `wait-for-booking-db` `initContainer` works cleanly?
4. What would break if we kept the schema in a Job (Stage 2 style) and
   only added a PVC?
5. Why does Stage 3 still have Jobs at all (`seed-*` Jobs and `pg-backup`
   `CronJob`)?
6. What is a `StorageClass` (`WaitForFirstConsumer`), and why does
   `pvc/pg-backups` remain `Pending` until the first `pg-backup` Job runs?
7. What happens when you `cordon` the node pinned in `PV.spec.nodeAffinity`
   and delete `identity-db-0`? How does network-attached CSI storage (Stage 9
   EBS) differ?
8. Why did we make `redis` a StatefulSet in Stage 3 instead of waiting
   for Stage 7?

---

## What comes next (Stage 4)

`livenessProbe`, `readinessProbe`, `startupProbe`, `resources.requests`,
`resources.limits`, `PodDisruptionBudget`, `LimitRange`, `ResourceQuota`, and
scheduling controls (`PriorityClass`, taints/tolerations, `nodeAffinity`,
`topologySpreadConstraints`). Probes give Kubernetes the signal to restart
unhealthy pods and pull unready pods from `EndpointSlice`s.

---

## Local HTTPS & Container Images

Envoy Gateway terminates TLS on `:443` using the runtime Secret
`apollo-tls-secret` in `apollo-airlines-apps` (created by
`scripts/generate-certs.sh`, preserved across `apply.sh` re-runs, and rotated
with `--rotate`). Local images are built and loaded into `kind` as
`apollo11/<service>:latest` via `scripts/build-images.sh --cluster <name>`,
with `https://` API URLs baked into the `frontend` bundle—always rebuild when
switching from an HTTP stage or another stage.

See the shared guides for full certificate, DNS, `mkcert`, and image-build
details:

- [Local HTTPS, TLS Certificates & Gateway Routing](../../docs/local-https.md)
- [CI Pipeline, Published GHCR Images & Local Image Contract](../../docs/ci-images.md)

Quick HTTPS verification in Stage 3 (`verify.sh` runs this automatically via `scripts/verify-tls.sh`):

```bash
export KUBE_CONTEXT=kind-apollo11   # or kind-apollo11-dev
bash scripts/verify-tls.sh
```
