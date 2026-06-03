---
title: "Stage 3: Mission Data — Persistent Storage, StatefulSets"
description: "Replace emptyDir volumes with PersistentVolumeClaims, convert databases to StatefulSets with stable pod identity, use init containers for DB schema seeding, and expose the frontend via Ingress."
---

# Stage 3: Mission Data

**Goal:** Give stateful services permanent storage that survives pod restarts.
Replace `emptyDir`-based storage with `PersistentVolumeClaims`, convert database
Deployments to `StatefulSets` for stable pod identity, move DB initialization into
init containers, and switch the frontend from NodePort to Ingress.

---

## What You'll Learn

| Concept | File(s) | What It Does |
|---|---|---|
| PersistentVolumeClaim | `**/sts.yaml` (VCT) | Requests durable storage that survives pod restarts |
| StatefulSet | `**/*-sts.yaml` | Pods with stable ordinal names, at-most-one semantics |
| VolumeClaimTemplate | `volumeClaimTemplates[]` | Per-pod PVC — each replica gets its own `data-<name>-<ordinal>` |
| Headless Service | `**/*-headless.yaml` | `clusterIP: None` — DNS returns pod IPs directly |
| Init container | `spec.initContainers[]` | Runs to completion before main container starts |
| Ingress (frontend) | `config/ingress.yaml` | Replaces NodePort — hostname routing for frontend.apollo11.local |

---

## Why Persistent Storage Matters

In stages 1 and 2, all databases used `emptyDir` volumes:

```
emptyDir     ←─ stage1/2
Pod deleted  →  data GONE  (emptyDir lives in node's RAM/disk, dies with pod)
Pod restarted → fresh empty volume
```

`emptyDir` is fine for **cache** (redis), terrible for **data** (postgres, sqlite).
Stage 3 switches to `PersistentVolumeClaim` backed by actual persistent storage:

```
PVC (1Gi, ReadWriteOnce)
  ↓
PV ( provisioned by StorageClass, survives pod death )
  ↓
Pod restarted → same PVC re-attached → data intact
```

---

## StatefulSet vs Deployment — What's Different

```
Deployment          StatefulSet
──────────────────  ─────────────────────────────────────────────────
app-A-xxxxx         app-0              ← ordinal, stable, predictable
app-A-yyyyy         app-1
app-B-zzzzz         (scale up: app-2; scale down: app-N-1 terminates first)

ClusterIP Service   Headless Service (clusterIP: None)
  ↓                  ↓
  VIP → backend      DNS → pod IPs directly (A records)
                     Pod identity: <name>-<ordinal>.<headless-svc>.<ns>.svc.cluster.local
```

**Key StatefulSet guarantees:**
- **Stable identity** — `auth-postgres-0` always gets the same PVC
- **At-most-one** — scale to 1 replica; no two `auth-postgres-0` exist simultaneously
- **Ordered deployment** — pod N starts only after pod N-1 is `Running`
- **Ordered termination** — scaling down terminates highest ordinal first

---

## Architecture (Stage 3)

```
┌─────────────────────────────────────────────────────────────────────┐
│  PersistentVolumeClaim (1Gi) — survives pod restart                │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────── apollo11-infra ───────────────────────────────────┐
│                                                                      │
│  auth-postgres      StatefulSet (1)    ┐                             │
│    └── PVC: data-auth-postgres-0      │ ← VolumeClaimTemplate        │
│    └── Headless SVC: auth-postgres-headless                           │
│    └── Init container: runs init.sql before postgres starts          │
│                                                                      │
│  catalog-postgres   StatefulSet (1)    ┐                             │
│    └── PVC: data-catalog-postgres-0   │                             │
│    └── Headless SVC: catalog-postgres-headless                       │
│    └── Init container: runs init.sql                                  │
│                                                                      │
│  circulation-postgres  StatefulSet (1) ┐                             │
│    └── PVC: data-circulation-postgres-0                             │
│    └── Headless SVC: circulation-postgres-headless                  │
│    └── Init container: runs init.sql                                 │
│                                                                      │
│  catalog-redis     StatefulSet (1)    ┐                              │
│    └── PVC: data-catalog-redis-0     │                              │
│    └── Headless SVC: catalog-redis-headless                         │
│                                                                      │
│  notification-redis  StatefulSet (1)  ┐                               │
│    └── PVC: data-notification-redis-0                                │
│    └── Headless SVC: notification-redis-headless                     │
│                                                                      │
│  NetworkPolicy: default-deny + per-service allowlist                │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────── apollo11-apps ────────────────────────────────────┐
│                                                                      │
│  auth/catalog/circulation/notification ─ Deployments (unchanged)    │
│                                                                      │
│  fines             StatefulSet (1)    ←─ NEW (was Deployment)         │
│    └── PVC: data-fines-0             ←─ SQLite now persists!        │
│    └── Headless SVC: fines-headless                                  │
│                                                                      │
│  Ingress (Traefik):                                                 │
│    frontend.apollo11.local → frontend:80                            │
│                                                                      │
│  NetworkPolicy: default-deny + allow from frontend                  │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────── apollo11-ui ───────────────────────────────────────┐
│                                                                      │
│  frontend        Deployment (2 replicas)                             │
│    └── nginx sidecar (port 80, serves static + proxies API)         │
│    └── ClusterIP Service: frontend (port 80) ← NOT NodePort         │
│                                                                      │
│  Ingress (Traefik):                                                 │
│    frontend.apollo11.local → frontend.apollo11-ui.svc.cluster.local  │
│                                                                      │
│  NetworkPolicy: allow 80/443 inbound                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Stable Pod Identity — DNS Names You Can Rely On

StatefulSet pods get stable FQDNs via their Headless Service:

```
auth-postgres-0.auth-postgres-headless.apollo11-infra.svc.cluster.local  →  pod IP
auth-postgres-1.auth-postgres-headless.apollo11-infra.svc.cluster.local  →  (if scaled)

fines-0.fines-headless.apollo11-apps.svc.cluster.local
```

This is why Headless services are required for StatefulSets — the pod ordinal
name-to-IP mapping comes from DNS, and clients can query it directly.

---

## Init Containers — Ordered Startup Before Main Container

Init containers run to completion **before** the main container starts.
For postgres StatefulSets, the init container:

1. Waits for postgres port to be ready (`pg_isready`)
2. Runs the init SQL script (`psql -f /init/init.sql`)
3. Exits 0 → main container starts

```yaml
initContainers:
  - name: init
    image: postgres:15-alpine
    command: ["sh", "-c", "pg_isready -h auth-postgres -U postgres && psql ..."]
    env:
      - name: PGPASSWORD
        valueFrom:
          secretKeyRef:
            name: apollo11-secrets
            key: POSTGRES_PASSWORD
    volumeMounts:
      - name: init-script
        mountPath: /init
```

**Why not use Init Jobs?** Jobs run once at cluster setup. Init containers
run on **every pod start** — useful when pods restart unexpectedly and need to
re-initialize. We keep the Init Jobs too (they seed the initial data).

---

## Frontend: NodePort → Ingress

Stage 2 used NodePort (`30080`) to expose the frontend. Stage 3 replaces it
with a Traefik Ingress:

```yaml
# Stage 2 (NodePort)
spec:
  type: NodePort
  ports:
    - port: 80
      nodePort: 30080

# Stage 3 (Ingress)
spec:
  type: ClusterIP        # internal only
  ports:
    - port: 80
      targetPort: 80
```

Ingress (in `apollo11-apps`) routes `frontend.apollo11.local` → `frontend.apollo11-ui` service.

---

## Manifest Structure

```
k8s/
├── config/
│   ├── namespace.yaml          # 3 namespaces (unchanged from stage2)
│   ├── serviceaccount.yaml     # 3 SAs (unchanged)
│   ├── configmap.yaml          # FQDN service URLs, DATABASE_PATH for fines
│   ├── secrets.yaml            # unchanged
│   └── ingress.yaml            # ADDED: frontend.apollo11.local route
├── infra/
│   ├── postgres/
│   │   ├── auth-postgres-sts.yaml      # StatefulSet + init container
│   │   ├── auth-postgres-svc-headless.yaml
│   │   ├── auth-postgres-netpol.yaml    # unchanged
│   │   └── auth-postgres-init-configmap.yaml
│   │   ├── catalog-postgres-sts.yaml
│   │   ├── catalog-postgres-svc-headless.yaml
│   │   ├── catalog-postgres-netpol.yaml
│   │   └── catalog-postgres-init-configmap.yaml
│   │   ├── circulation-postgres-sts.yaml
│   │   ├── circulation-postgres-svc-headless.yaml
│   │   ├── circulation-postgres-netpol.yaml
│   │   └── circulation-postgres-init-configmap.yaml
│   └── redis/
│       ├── catalog-redis-sts.yaml
│       ├── catalog-redis-svc-headless.yaml
│       ├── catalog-redis-netpol.yaml
│       ├── notification-redis-sts.yaml
│       ├── notification-redis-svc-headless.yaml
│       └── notification-redis-netpol.yaml
├── apps/
│   ├── auth/                   # Deployment (unchanged from stage2)
│   ├── catalog/                # Deployment (unchanged)
│   ├── circulation/            # Deployment (unchanged)
│   ├── notification/           # Deployment (unchanged)
│   └── fines/
│       ├── fines-sts.yaml      # NEW — StatefulSet (was fines-dep.yaml)
│       ├── fines-svc-headless.yaml  # NEW — Headless (was fines-svc.yaml)
│       └── fines-netpol.yaml   # unchanged
├── ui/
│   └── frontend/
│       ├── frontend-dep.yaml   # updated (removed NodePort annotations)
│       ├── frontend-svc.yaml   # ClusterIP only (no NodePort)
│       ├── frontend-netpol.yaml
│       └── frontend-ingress.yaml  # NEW — Traefik Ingress
└── jobs/                        # Init jobs (unchanged from stage2)
    ├── init-auth-db.yaml
    ├── init-catalog-db.yaml
    └── init-circulation-db.yaml
```

---

## Deploy

### 1. Build the container images

```bash
cd /home/darshan/projects/Apollo11/stages/stage3
./scripts/build-images.sh
```

### 2. Apply manifests in dependency order

```bash
# Layer 1: Namespaces + ServiceAccounts
kubectl apply -f k8s/config/namespace.yaml
kubectl apply -f k8s/config/serviceaccount.yaml

# Layer 2: ConfigMap + Secrets
kubectl apply -f k8s/config/configmap.yaml
kubectl apply -f k8s/config/secrets.yaml

# Layer 3: Ingress (controller must be running first)
kubectl apply -f k8s/config/ingress.yaml

# Layer 4: Infrastructure StatefulSets (wait for namespaces)
kubectl apply -f k8s/infra/postgres/
kubectl apply -f k8s/infra/redis/

# Layer 5: Application StatefulSet (fines) + Deployments
kubectl apply -f k8s/apps/fines/
kubectl apply -f k8s/apps/auth/
kubectl apply -f k8s/apps/catalog/
kubectl apply -f k8s/apps/circulation/
kubectl apply -f k8s/apps/notification/

# Layer 6: UI (Ingress exposes frontend)
kubectl apply -f k8s/ui/frontend/

# Layer 7: Init Jobs (seeds data — run after DBs are ready)
kubectl apply -f k8s/jobs/
```

### 3. Watch StatefulSet rollout

```bash
kubectl get pods -n apollo11-infra -w
kubectl get pods -n apollo11-apps -w
kubectl get pods -n apollo11-ui -w

# Check PVC binding
kubectl get pvc -A
```

---

## Access the Services

**Frontend via Ingress (add to /etc/hosts first):**

```bash
# Add to /etc/hosts:
127.0.0.1 frontend.apollo11.local api.apollo11.local catalog.apollo11.local

# Then access:
curl http://frontend.apollo11.local/
```

**Port-forward individual services:**

```bash
# Auth service in apollo11-apps
kubectl port-forward -n apollo11-apps svc/auth 8080:8080

# Fines StatefulSet (stable pod name)
kubectl port-forward -n apollo11-apps svc/fines-headless 8084:8084
kubectl port-forward -n apollo11-infra pods/auth-postgres-0 5432:5432
```

---

## Self-Check

Run the automated test script:

```bash
cd /home/darshan/projects/Apollo11
bash stages/stage3/test/stage3_test.sh
```

The script verifies:
- All 3 namespaces exist
- 6 StatefulSets (3 postgres + 2 redis + fines)
- 6 PVCs bound (1Gi each)
- 6 Headless services (`clusterIP: None`)
- Init containers terminated successfully (exit 0) in postgres StatefulSets
- Init ConfigMaps present (3 postgres init scripts)
- Frontend Ingress exists (`frontend.apollo11.local`)
- Frontend Service is ClusterIP (not NodePort)
- Init Jobs completed (1/1)
- NetworkPolicies present across all namespaces
- Stable pod ordinal names (e.g. `auth-postgres-0`)

---

## Clean Up

Delete StatefulSets (PVCs are NOT deleted automatically — must delete manually):

```bash
kubectl delete -f k8s/jobs/
kubectl delete -f k8s/ui/frontend/
kubectl delete -f k8s/apps/notification/
kubectl delete -f k8s/apps/circulation/
kubectl delete -f k8s/apps/catalog/
kubectl delete -f k8s/apps/fines/
kubectl delete -f k8s/infra/redis/
kubectl delete -f k8s/infra/postgres/
kubectl delete -f k8s/config/ingress.yaml
kubectl delete -f k8s/config/serviceaccount.yaml
kubectl delete -f k8s/config/namespace.yaml

# PVCs persist — delete them explicitly to free storage
kubectl delete pvc --all -n apollo11-infra
kubectl delete pvc --all -n apollo11-apps
```

Or delete entire namespaces at once (cascades to all resources + PVCs):

```bash
kubectl delete namespace apollo11-infra apollo11-apps apollo11-ui
```

---

## Key Takeaways

```
emptyDir          → data dies with pod (cache only, fine for redis)
PersistentVolume  → network-attached storage, survives cluster restarts
PVC               → request for PV storage (bind, reclaim, capacity)

StatefulSet        → stable ordinal names + at-most-one semantics
  serviceName      → required! must match Headless Service name
  volumeClaimTemplate → per-replica PVC (each gets unique volume)
  ordered deployment/termination (N-1 must be Running before N starts)

Headless Service  → clusterIP: None → DNS returns pod IPs directly
  <name>-<ordinal>.<headless-svc>.<ns>.svc.cluster.local  ← stable FQDN
  Used by StatefulSets for pod discovery; clients do their own load-balancing

Init container    → runs to completion before main container
  pg_isready → wait for DB port
  psql -f    → run idempotent init SQL
  init containers re-run on EVERY pod restart (use IF NOT EXISTS / ON CONFLICT DO NOTHING)

Ingress (frontend)→ NodePort deprecated: frontend.apollo11.local → ClusterIP service
  Traefik watches Ingress resources, routes by hostname
  frontend-svc stays ClusterIP — Ingress handles external traffic

PVC reclaim policy → Retain (manual cleanup) or Delete (auto cleanup on PVC delete)
  Default is Delete — data gone when PVC is deleted
```

---

## What's Next

Stage 4 introduces **probes and resource management** — liveness, readiness,
and startup probes to keep pods healthy, resource requests/limits for CPU
and memory, QoS classes that affect scheduling priority, and PodDisruptionBudgets
for safe cluster operations.

**Before moving on, make sure you can answer:**

1. Why does data survive a pod restart with a PVC but not with an emptyDir?
2. What does `serviceName: auth-postgres-headless` in a StatefulSet spec do?
3. How does a Headless Service give a pod a stable DNS name?
4. When does an init container run — once at cluster setup, or every pod restart?
5. Why is the init SQL script idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`)?
6. What happens to PVCs when you `kubectl delete` a StatefulSet?
7. Why does the frontend service no longer need NodePort in stage 3?
8. What's the difference between `volumeMounts` in the main container vs. in the pod spec?