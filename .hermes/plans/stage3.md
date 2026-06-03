# Stage 3 Plan — Mission Data (Persistent Storage)

## Goal
Replace `emptyDir`-based Deployments with `StatefulSet` + `PersistentVolumeClaim` for all 5 databases. Add init containers so DB schema seeding happens automatically before postgres starts. Replace frontend NodePort with Traefik Ingress. Add Headless services for StatefulSet pod discovery.

---

## Delta from Stage 2

| What's changing | Stage 2 | Stage 3 |
|---|---|---|
| DB pods | Deployment + emptyDir | StatefulSet + VolumeClaimTemplate (1Gi) |
| DB init | Separate init Job | Init container inside StatefulSet (runs before main container) |
| Init data volume | emptyDir | Persistent Volume (same PVC, shared rw across containers) |
| Stateful DB services | ClusterIP | Headless (clusterIP: None) for stable pod DNS |
| Frontend | NodePort :30080 | Traefik Ingress (frontend.apollo11.local) |
| Fines service | emptyDir SQLite | Persistent PVC (1Gi) |
| ConfigMap | ClusterIP FQDNs | Headless FQDNs for stateful services |

---

## k8s Manifest Changes (48 files total)

### config/ (4 files — all modified)
- `namespace.yaml` — unchanged (same 3 NS from stage2)
- `serviceaccount.yaml` — unchanged
- `configmap.yaml` — update stateful service URLs to Headless FQDNs:
  - `catalog-postgres.apollo11-infra.svc.cluster.local` (Headless → resolves to pod IP)
  - `circulation-postgres.apollo11-infra.svc.cluster.local`
  - `auth-postgres.apollo11-infra.svc.cluster.local`
  - `catalog-redis.apollo11-infra.svc.cluster.local`
  - `notification-redis.apollo11-infra.svc.cluster.local`
  - Frontend URL now via Ingress, not NodePort
- `secrets.yaml` — unchanged

### infra/postgres/ (9 files → 15 files)
Each postgres becomes StatefulSet (replaces Deployment) + Headless Service (replaces ClusterIP) + unchanged NetworkPolicy + **NEW**: init container + shared init volume

For each of 3 postgres services (auth-postgres, catalog-postgres, circulation-postgres):
- `*-sts.yaml` — StatefulSet (was `*-dep.yaml`)
  - `serviceName: <name>-headless` (required for StatefulSet)
  - `VolumeClaimTemplate` with 1Gi standard storage
  - Init container: waits for postgres, runs init.sql
  - Main container: postgres with init volume mounted at `/docker-entrypoint-initdb.d/`
- `*-svc-headless.yaml` — Headless Service (was `*-svc.yaml`)
  - `clusterIP: None`
  - Port 5432
- `*-netpol.yaml` — unchanged
- `*-init-configmap.yaml` — **NEW** (holds init.sql, mounted into StatefulSet)

### infra/redis/ (6 files → 9 files)
Redis StatefulSets (2 services: catalog-redis, notification-redis):
- `*-sts.yaml` — StatefulSet (was `*-dep.yaml`)
  - VolumeClaimTemplate 1Gi (redis persistence)
  - Init container: redis-cli ping check + save test
- `*-svc-headless.yaml` — Headless Service (was `*-svc.yaml`)
  - `clusterIP: None`
- `*-netpol.yaml` — unchanged
- (No init configmap for redis — init container runs inline script)

### apps/fines/ (3 files → 5 files)
- `fines-sts.yaml` — **NEW StatefulSet** (replaces fines-dep.yaml)
  - VolumeClaimTemplate 1Gi for SQLite persistence
  - No init container (fines doesn't need DB init)
- `fines-svc-headless.yaml` — **NEW Headless Service** (fines needs stable pod identity for SQLite)
  - `clusterIP: None`, port 8084
- `fines-netpol.yaml` — unchanged
- `fines-dep.yaml` — **DELETE** (replaced by StatefulSet)
- `fines-svc.yaml` — **DELETE** (replaced by Headless)
- `fines-init-configmap.yaml` — **NEW** (empty placeholder, keeps pattern consistent)

### apps/ (auth/catalog/circulation/notification — 12 files, all unchanged)
These are application services (not databases). Stage2 Deployments + ClusterIP Services remain unchanged.
Wait — check stage2: auth/catalog/circulation/notification are all Go/Python microservices, NOT databases. Correct — they stay as Deployments.

### ui/frontend/ (3 files → 4 files)
- `frontend-ingress.yaml` — **NEW Traefik Ingress** (replaces NodePort)
  - `host: frontend.apollo11.local` → service `frontend.apollo11-ui.svc.cluster.local` port 80
- `frontend-dep.yaml` — **DELETE** (frontend stays Deployment but with Ingress, not NodePort)
- `frontend-svc.yaml` — **MODIFY** — remove NodePort, keep ClusterIP
- `frontend-netpol.yaml` — unchanged

### jobs/ (3 files → 1 file)
Init Jobs are **REPLACED** by init containers inside StatefulSets. The init container pattern is:
1. Init container waits for postgres port (nc -z)
2. Init container waits for postgres ready (pg_isready)
3. Init container runs init.sql via psql (mounted from ConfigMap)
4. Init container exits 0 → main container starts
This is a one-time cost per pod启动 (not per restart — init container re-runs on each pod start, which is fine for idempotent init scripts).

However, the init Jobs are still needed for the **initial schema creation and seed data** because StatefulSet init containers run on EVERY pod restart. The correct approach:
- Keep init jobs (they run once after cluster setup to seed data)
- Add init containers inside StatefulSet to handle postgres startup ordering

Actually wait: StatefulSet with init container = init container runs BEFORE main container. If we use idempotent init scripts (IF NOT EXISTS, INSERT ON CONFLICT DO NOTHING), re-running on pod restart is fine. This is cleaner than separate init jobs.

Decision: **Keep init jobs as-is for stage3**. The init container pattern is a stage4+ addition (startup/liveness/readiness probes). Stage3 init jobs remain.

### config/ingress.yaml — **MODIFY**
Add frontend.apollo11.local route to existing Traefik Ingress:
```yaml
- host: frontend.apollo11.local
  http:
    paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
```

---

## Code Changes (stage3/code/)

All code is copied from stage2 — no changes needed. The code doesn't care whether it's Deployment or StatefulSet.

---

## New Files to Create

```
stages/stage3/
├── k8s/
│   ├── config/
│   │   ├── configmap.yaml           # MODIFY — Headless FQDNs + frontend ingress URL
│   │   └── ingress.yaml              # MODIFY — add frontend.apollo11.local route
│   ├── infra/
│   │   ├── postgres/
│   │   │   ├── auth-postgres-sts.yaml
│   │   │   ├── auth-postgres-svc-headless.yaml
│   │   │   ├── auth-postgres-init-configmap.yaml   # NEW
│   │   │   ├── auth-postgres-netpol.yaml           # unchanged
│   │   │   ├── catalog-postgres-sts.yaml
│   │   │   ├── catalog-postgres-svc-headless.yaml
│   │   │   ├── catalog-postgres-init-configmap.yaml
│   │   │   ├── catalog-postgres-netpol.yaml
│   │   │   ├── circulation-postgres-sts.yaml
│   │   │   ├── circulation-postgres-svc-headless.yaml
│   │   │   ├── circulation-postgres-init-configmap.yaml
│   │   │   └── circulation-postgres-netpol.yaml
│   │   └── redis/
│   │       ├── catalog-redis-sts.yaml
│   │       ├── catalog-redis-svc-headless.yaml
│   │       ├── catalog-redis-netpol.yaml
│   │       ├── notification-redis-sts.yaml
│   │       ├── notification-redis-svc-headless.yaml
│   │       └── notification-redis-netpol.yaml
│   ├── apps/
│   │   ├── fines/
│   │   │   ├── fines-sts.yaml        # NEW — StatefulSet replacing fines-dep.yaml
│   │   │   ├── fines-svc-headless.yaml
│   │   │   ├── fines-netpol.yaml
│   │   │   └── fines-init-configmap.yaml
│   │   ├── auth/                     # unchanged (Deployment)
│   │   ├── catalog/                  # unchanged
│   │   ├── circulation/              # unchanged
│   │   └── notification/             # unchanged
│   └── ui/
│       └── frontend/
│           ├── frontend-ingress.yaml  # NEW
│           ├── frontend-svc.yaml      # MODIFY — remove NodePort, ClusterIP
│           └── frontend-netpol.yaml
├── scripts/
│   └── build-images.sh               # copy from stage2
├── test/
│   └── stage3_test.sh
├── code/                              # copied from stage2 (no code changes)
└── README.md
```

**Files to DELETE from stage2/k8s that don't carry forward:**
- infra/postgres/*-dep.yaml (replaced by *-sts.yaml)
- infra/postgres/*-svc.yaml (replaced by *-svc-headless.yaml)
- infra/redis/*-dep.yaml (replaced by *-sts.yaml)
- infra/redis/*-svc.yaml (replaced by *-svc-headless.yaml)
- apps/fines/fines-dep.yaml (replaced by fines-sts.yaml)
- apps/fines/fines-svc.yaml (replaced by fines-svc-headless.yaml)
- ui/frontend/frontend-dep.yaml (replaced by updated version)
- ui/frontend/frontend-svc.yaml (NodePort removed)

---

## Implementation Order

1. Create directory structure
2. Copy + transform config files (namespace, SA, secrets — unchanged; configmap + ingress — updated)
3. Create infra/postgres StatefulSets with init containers + Headless services + init ConfigMaps
4. Create infra/redis StatefulSets with Headless services
5. Create apps/fines StatefulSet + Headless service + init configmap
6. Create ui/frontend Ingress + update Service (remove NodePort)
7. Keep jobs/ init jobs as-is (unchanged from stage2)
8. Create build-images.sh
9. Create stage3_test.sh
10. Create README.md

---

## Key Concepts (for README)

1. **PersistentVolumeClaim** — requested storage, survives pod restarts
2. **StatefulSet vs Deployment** — stable identity, ordinal pod names, at-most-one semantics
3. **VolumeClaimTemplate** — per-pod PVC, each pod gets its own `data-<name>-<ordinal>` volume
4. **Init containers** — ordered execution before main container, shared volume for init scripts
5. **Headless service** (`clusterIP: None`) — DNS round-robin over pod IPs, stable pod FQDNs
6. **Pod identity** — `postgres-0.auth-postgres.apollo11-infra.svc.cluster.local` is stable
7. **Ingress for frontend** — external access replaces NodePort

---

## Test Coverage (stage3_test.sh)

1. namespaces exist (infra/apps/ui)
2. StatefulSets created (5 infra + fines = 6 total StatefulSets)
3. PVCs bound (6 PVCs, 1 per StatefulSet pod)
4. Headless services (5 infra + fines = 6 Headless services)
5. Init containers completed successfully (ContainerCreated → Running → Terminated)
6. Init ConfigMaps present (3 postgres init scripts)
7. Frontend Ingress exists (host: frontend.apollo11.local)
8. Frontend Service is ClusterIP (not NodePort)
9. Replica counts (all StatefulSets: 1 replica each)
10. NetworkPolicies still present
11. Init Jobs still complete successfully

---

## Build + Deploy Sequence

```bash
cd /home/darshan/projects/Apollo11/stages/stage3

# Namespaces + SA + Config + Secrets
kubectl apply -f k8s/config/namespace.yaml
kubectl apply -f k8s/config/serviceaccount.yaml
kubectl apply -f k8s/config/configmap.yaml
kubectl apply -f k8s/config/secrets.yaml

# Ingress + Gateway (controllers need this first)
kubectl apply -f k8s/config/ingress.yaml

# Infrastructure (StatefulSets — wait for namespace)
kubectl apply -f k8s/infra/postgres/
kubectl apply -f k8s/infra/redis/

# Apps (fines becomes StatefulSet, others unchanged)
kubectl apply -f k8s/apps/fines/
kubectl apply -f k8s/apps/auth/
kubectl apply -f k8s/apps/catalog/
kubectl apply -f k8s/apps/circulation/
kubectl apply -f k8s/apps/notification/

# UI (frontend now has Ingress)
kubectl apply -f k8s/ui/frontend/

# Init Jobs (unchanged from stage2)
kubectl apply -f k8s/jobs/
```
