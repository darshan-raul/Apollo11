---
title: "Stage 1: Liftoff — Kubernetes Deployments"
description: "Deploy all 11 services to a kind cluster using Deployments, ConfigMaps, Secrets, and Jobs."
---

# Stage 1: Liftoff

**Goal:** Deploy all 11 services to a Kubernetes cluster using
Deployments, ConfigMaps, Secrets, and Jobs — and understand every field
in every manifest.

## What You'll Learn

| Concept | File(s) | What It Does |
|---|---|---|
| Namespace | `config/namespace.yaml` | Logical isolation boundary |
| ConfigMap | `config/configmap.yaml` | Non-sensitive configuration |
| Secret | `config/secrets.yaml` | Sensitive data ( passwords, tokens ) |
| Deployment | `infra/**/dep.yaml`, `apps/**/dep.yaml` | Declarative pod management with replicas |
| Service | `apps/**/svc.yaml` | Stable network endpoint for pods |
| Job | `jobs/init-*.yaml` | One-time task to completion |
| emptyDir volume | `infra/**/dep.yaml` | Ephemeral storage ( cleared on pod restart ) |
| Kustomize | `k8s/kustomization.yaml` | Composes all sub-components into one apply |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Namespace: apollo11                                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ConfigMap (apollo11-config)    Secret (apollo11-secrets)  │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌──infra─────────────────┐  ┌──apps──────────────────────────┐  │
│  │ auth-postgres  (×1)    │  │  auth      (×2) ─┐             │  │
│  │ catalog-postgres (×1)  │  │  catalog   (×2) ├─ Service     │  │
│  │ circulation-pg (×1)   │  │  circulation(×2) │             │  │
│  │ catalog-redis (×1)    │  │  notification(×2) │             │  │
│  │ notification-redis(×1) │  │  fines     (×2) │             │  │
│  └────────────────────────┘  │  frontend  (×2) ─┘             │  │
│                              └──────────────────────────────────┘  │
│  ┌──jobs───────────────────────────────────────────────────────┐  │
│  │  init-auth-db  init-catalog-db  init-circulation-db        │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## The Reconciliation Loop

Kubernetes never directly creates Pods. A Deployment manages the loop:

```
┌────────────┐      ┌───────────────┐      ┌─────────────┐
│ Deployment  │ ───▶ │  ReplicaSet    │ ───▶ │  Pods        │
│ (desired    │      │  (matches     │      │  (running    │
│  state)     │      │   replica     │      │   instances) │
│              │      │   count)      │      │              │
│ spec:        │      │               │      │              │
│  replicas: 2 │ ───▶ │  [pod] [pod]  │ ───▶ │  [●] [●]     │
└────────────┘      └───────────────┘      └─────────────┘
                       └── selector ──────▶ labels: app: auth
```

If a Pod crashes, the ReplicaSet replaces it. If you change `replicas: 3`,
the ReplicaSet creates one more Pod. If you change the container image,
the ReplicaSet rolls out a new version.

---

## Manifest Anatomy — Deployment

`apps/auth/auth-dep.yaml`:

```yaml
apiVersion: apps/v1          # Group/Version for the Deployment CRD
kind: Deployment            # Tell k8s this is a Deployment

metadata:
  name: auth                # Unique name within the namespace
  namespace: apollo11        # Which namespace this belongs to

spec:
  replicas: 2               # Always keep 2 copies running

  selector:                 # How this Deployment finds its Pods
    matchLabels:            # ReplicaSet picks pods with matching labels
      app: auth

  template:                 # The Pod spec (not a full Pod — a template)
    metadata:
      labels:
        app: auth           # Applied to every Pod this Deployment creates
    spec:
      containers:
        - name: auth
          image: apollo11/auth:latest   # Custom image we built earlier
          imagePullPolicy: IfNotPresent # Use local image, don't pull remotely

          ports:
            - containerPort: 8080       # Port the container listens on

          # ── Environment Variables ──────────────────────────────────────
          # Option A: hardcoded inline value
          env:
            - name: PORT
              value: "8080"

            # Option B: reference a key inside a Secret
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: apollo11-secrets    # Which Secret
                  key: JWT_SECRET           # Which key inside that Secret

          # Option C: reference all keys from a ConfigMap as env vars
          envFrom:
            - configMapRef:
                name: apollo11-config       # Injects every key as VAR=VALUE

          # ── Health Probes ───────────────────────────────────────────────
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5    # Wait 5s after container start
            periodSeconds: 5          # Check every 5s

          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
```

### Why Both `env` and `envFrom`?

```
env:                               envFrom:
  - name: JWT_SECRET                 - configMapRef:
      valueFrom:                       name: apollo11-config
        secretKeyRef:                    ↓
        name: apollo11-secrets         Injects ALL keys:
        key: JWT_SECRET                 AUTH_SERVICE_URL, CATALOG_SERVICE_URL,
                                       PORT_FRONTEND, etc.
```

Use `env` (inline) for: secrets, values that must be exact.
Use `envFrom` (configMapRef) for: non-sensitive config that might grow.

### `imagePullPolicy: IfNotPresent`

```
Kind cluster has image locally?  →  Use local copy (fast, no network)
Kind cluster missing image?      →  Fail deployment
```

For development images built with `kind load`, `IfNotPresent` is correct.
For production, use `Always` to ensure you always get the latest tagged build.

---

## Manifest Anatomy — Service

`apps/catalog/catalog-svc.yaml`:

```yaml
apiVersion: v1
kind: Service

metadata:
  name: catalog
  namespace: apollo11

spec:
  selector:
    app: catalog          # Route traffic to any Pod with label app=catalog

  ports:
    - port: 8081          # The Service's stable IP:port (cluster-wide)
      targetPort: 8081   # Forward to this port ON the Pod
```

### Service Types

| Type | Use Case | External Access |
|---|---|---|
| **ClusterIP** | Internal services (auth, catalog, etc.) | No — cluster-internal only |
| **NodePort** | Development, simple external access | Yes — `http://<node-ip>:30080` |
| **LoadBalancer** | Cloud (AWS/GCP/Azure) — allocates cloud LB | Yes — provisions cloud LB |

`frontend-svc.yaml` is a NodePort (to make the frontend accessible without
a cloud LoadBalancer):

```yaml
spec:
  type: NodePort
  ports:
    - port: 80             # Service port (cluster-internal)
      targetPort: 80       # Pod nginx listens on 80
      nodePort: 30080      # Exposed on every node at port 30080
```

To access the frontend: `http://<your-node-ip>:30080`
On kind (single node): `http://localhost:30080`

---

## Manifest Anatomy — ConfigMap & Secret

`config/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: apollo11-config
  namespace: apollo11
data:                    # key: value pairs — all strings
  PORT_AUTH: "8080"
  AUTH_SERVICE_URL: "http://auth:8080"
  CATALOG_DB: "catalog"
  DATABASE_PATH: "/data/fines.db"
```

`config/secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: apollo11-secrets
  namespace: apollo11
type: Opaque             # Generic key-value secret (vs TLS, docker-registry, etc.)
stringData:              # Write plain text; k8s stores it base64-encoded
  POSTGRES_PASSWORD: "postgres"
  JWT_SECRET: "apollo11-dev-secret-change-in-production"
```

> **Security note:** In production, never store secrets in plain YAML.
> Use Sealed Secrets (stage 8), HashiCorp Vault, or AWS Secrets Manager.
> The Secret object itself is **not encrypted** by default in vanilla k8s —
> it only base64-encodes, which is not encryption. Enable Encryption at Rest.

---

## Manifest Anatomy — Job (Database Init)

`jobs/init-auth-db.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: init-auth-db
  namespace: apollo11
spec:
  backoffLimit: 3        # Retry failed pods up to 3 times

  template:
    metadata:
      labels:
        app: init-auth-db
    spec:
      containers:
        - name: init
          image: postgres:15-alpine   # Same image as the DB itself
          command:
            - sh
            - -c
            - |
              # Wait for the DB to be ready before running SQL
              until pg_isready -h auth-postgres -U postgres; do
                echo "Waiting for auth-postgres..."
                sleep 2
              done

              # Run the init SQL script
              psql -h auth-postgres -U postgres -d auth -f /init/init.sql || true

              echo "auth DB init done"

          env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: apollo11-secrets
                  key: POSTGRES_PASSWORD

          volumeMounts:
            - name: init-script
              mountPath: /init       # ConfigMap content mounted here

      volumes:
        - name: init-script
          configMap:
            name: auth-init-script  # References the ConfigMap with init.sql

      restartPolicy: OnFailure       # Don't keep restarting the Job pod
```

`jobs/auth-init-configmap.yaml` contains the SQL:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-init-script
  namespace: apollo11
data:
  init.sql: |             # Multi-line string (YAML block scalar)
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        ...
    );
    INSERT INTO users ...; # Seeds admin user (admin@apollo11.local / admin123)
```

### Why a Job, Not a Sidecar?

The init container pattern (stage 3) runs SQL on every pod start.
The Job pattern runs SQL once, then exits. For database schema setup,
the Job pattern is correct — we don't want to re-run `CREATE TABLE`
every time a pod restarts.

---

## Manifest Anatomy — emptyDir Volume

`infra/postgres/auth-postgres-dep.yaml` (relevant section):

```yaml
spec:
  containers:
    - name: postgres
      ...
      volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data   # PostgreSQL stores DB here

  volumes:
    - name: pg-data
      emptyDir: {}                               # Kubernetes allocates temp storage
```

### emptyDir Lifecycle

```
Pod scheduled ──▶ emptyDir allocated on node ──▶ Pod writes to /var/lib/...
                                                                  │
Pod terminated ◀──────────────────────────────────────────────────┘
        │
        └── emptyDir is DELETED (ephemeral — data lost)
```

### Why emptyDir for Postgres/Redis Here?

Stage 1 is about deploying workloads, not persistent storage.
emptyDir is the simplest volume type — no storage provisioner needed.
Stage 3 replaces emptyDir with PersistentVolumeClaims (durable storage).

---

## Manifest Anatomy — Namespace

`config/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: apollo11
  labels:
    app.kubernetes.io/name: apollo11     # Common label for all resources
    app.kubernetes.io/component: namespace
```

All other manifests reference `namespace: apollo11`. The namespace
acts as a scope boundary — resources in one namespace can't accidentally
reference resources in another by name alone.

---

## Manifest Structure (apply in this order)

Kubernetes resources have dependencies. Apply them in this sequence:

```
k8s/
├── config/
│   ├── namespace.yaml       # 1. Create the namespace first
│   ├── configmap.yaml       # 2. Config (non-sensitive)
│   └── secrets.yaml         # 3. Secrets (sensitive)
├── infra/
│   ├── postgres/
│   │   ├── auth-postgres-dep.yaml
│   │   ├── auth-postgres-svc.yaml
│   │   ├── catalog-postgres-dep.yaml
│   │   ├── catalog-postgres-svc.yaml
│   │   ├── circulation-postgres-dep.yaml
│   │   └── circulation-postgres-svc.yaml
│   └── redis/
│       ├── catalog-redis-dep.yaml
│       ├── catalog-redis-svc.yaml
│       ├── notification-redis-dep.yaml
│       └── notification-redis-svc.yaml
├── apps/
│   ├── auth/
│   │   ├── auth-dep.yaml
│   │   └── auth-svc.yaml
│   ├── catalog/
│   │   ├── catalog-dep.yaml
│   │   └── catalog-svc.yaml
│   ├── circulation/
│   │   ├── circulation-dep.yaml
│   │   └── circulation-svc.yaml
│   ├── notification/
│   │   ├── notification-dep.yaml
│   │   └── notification-svc.yaml
│   ├── fines/
│   │   ├── fines-dep.yaml
│   │   └── fines-svc.yaml
│   └── frontend/
│       ├── frontend-dep.yaml
│       └── frontend-svc.yaml
└── jobs/
    ├── auth-init-configmap.yaml
    ├── init-auth-db.yaml
    ├── catalog-init-configmap.yaml
    ├── init-catalog-db.yaml
    ├── circulation-init-configmap.yaml
    └── init-circulation-db.yaml
```

**Why the order matters:**

```
config/namespace.yaml
        ↓
config/configmap.yaml + secrets.yaml   ← infra/ depends on namespace
        ↓
infra/postgres + infra/redis           ← apps/ depend on infra services
        ↓
apps/ (auth, catalog, etc.)           ← jobs/ run DB init after DBs are up
        ↓
jobs/ (init-*-db.yaml)
```

Each layer is built on the previous. If you apply `apps/` before
`infra/`, the application pods will fail to resolve the database hostnames
(`auth-postgres`, `catalog-postgres`, etc.) because those Services don't
exist yet.

---

## All 11 Services

```
┌─────────────────┬────────┬─────────────┬────────────────────────────┐
│ Service          │  Port  │ Type        │ Backend                    │
├─────────────────┼────────┼─────────────┼────────────────────────────┤
│ auth-postgres   │  5432  │ ClusterIP   │ (PostgreSQL 15)            │
│ catalog-postgres│  5432  │ ClusterIP   │ (PostgreSQL 15)            │
│ circulation-pg  │  5432  │ ClusterIP   │ (PostgreSQL 15)            │
│ catalog-redis   │  6379  │ ClusterIP   │ (Redis 7)                   │
│ notification-rd │  6380  │ ClusterIP   │ (Redis 7)                   │
│ auth            │  8080  │ ClusterIP   │ auth-postgres (5432)        │
│ catalog         │  8081  │ ClusterIP   │ catalog-postgres (5432)     │
│                  │        │             │ catalog-redis (6379)       │
│ circulation     │  8082  │ ClusterIP   │ circulation-postgres (5432) │
│ notification    │  8083  │ ClusterIP   │ notification-redis (6380)   │
│ fines           │  8084  │ ClusterIP   │ — (SQLite on emptyDir)     │
│ frontend        │   80   │ NodePort    │ (nginx + Go, port 30080)    │
└─────────────────┴────────┴─────────────┴────────────────────────────┘
```

---

## Deploy

### 1. Build the container images

```bash
cd /home/darshan/projects/Apollo11/stages/stage1
./scripts/build-images.sh
```

This builds all 6 service images and loads them into your kind cluster.

### 2. Apply manifests in dependency order

Apply each layer in sequence — each layer depends on the previous:

```bash
# Layer 1: Namespace must exist first
kubectl apply -f k8s/config/namespace.yaml

# Layer 2: ConfigMap and Secrets (need the namespace)
kubectl apply -f k8s/config/configmap.yaml
kubectl apply -f k8s/config/secrets.yaml

# Layer 3: Infrastructure (postgres, redis — apps depend on these)
kubectl apply -f k8s/infra/postgres/
kubectl apply -f k8s/infra/redis/

# Layer 4: Application services
kubectl apply -f k8s/apps/auth/
kubectl apply -f k8s/apps/catalog/
kubectl apply -f k8s/apps/circulation/
kubectl apply -f k8s/apps/notification/
kubectl apply -f k8s/apps/fines/
kubectl apply -f k8s/apps/frontend/

# Layer 5: Database init jobs (run after DBs are ready)
kubectl apply -f k8s/jobs/
```

Or apply everything at once — Kubernetes resolves the order internally:

```bash
# Apply all at once (k8s resolves dependencies by name)
kubectl apply -f k8s/config/
kubectl apply -f k8s/infra/ --recursive
kubectl apply -f k8s/apps/ --recursive
kubectl apply -f k8s/jobs/
```

> **Tip:** Using `-f <dir>/` (directory) applies all `.yaml` files in that
> directory. Using `--recursive` descends into subdirectories.

---

## Self-Check

Run the automated test script:

```bash
cd /home/darshan/projects/Apollo11
bash test/stage1_test.sh
```

If all checks pass, your cluster is correctly configured. If checks fail,
the script tells you which resource is missing or not ready.

---

## Access the Services

**Frontend (NodePort, port 30080):**

```bash
kubectl get svc -n apollo11 frontend
# Access: http://localhost:30080  (kind) or http://<node-ip>:30080
```

**Internal services (port-forward for testing):**

```bash
# Auth service
kubectl port-forward -n apollo11 svc/auth 8080:8080
curl http://localhost:8080/health

# Catalog service
kubectl port-forward -n apollo11 svc/catalog 8081:8081
curl http://localhost:8081/health

# Circulation service
kubectl port-forward -n apollo11 svc/circulation 8082:8082
curl http://localhost:8082/health

# Fines service
kubectl port-forward -n apollo11 svc/fines 8084:8084
curl http://localhost:8084/health

# Notification service
kubectl port-forward -n apollo11 svc/notification 8083:8083
curl http://localhost:8083/health
```

**Login to the auth service:**

```bash
# Register a new user
curl -X POST http://localhost:8080/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test1234","full_name":"Test User"}'

# Login (returns JWT)
curl -X POST http://localhost:8080/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apollo11.local","password":"admin123"}'
```

---

## Clean Up

Delete all resources in dependency order (reverse of apply):

```bash
# Delete jobs first (no dependencies)
kubectl delete -f k8s/jobs/

# Delete app services
kubectl delete -f k8s/apps/frontend/
kubectl delete -f k8s/apps/fines/
kubectl delete -f k8s/apps/notification/
kubectl delete -f k8s/apps/circulation/
kubectl delete -f k8s/apps/catalog/
kubectl delete -f k8s/apps/auth/

# Delete infra
kubectl delete -f k8s/infra/redis/
kubectl delete -f k8s/infra/postgres/

# Delete config last (everything else must be gone first)
kubectl delete -f k8s/config/secrets.yaml
kubectl delete -f k8s/config/configmap.yaml
kubectl delete -f k8s/config/namespace.yaml
```

Or delete the whole namespace (quickest):

```bash
kubectl delete namespace apollo11
```

This immediately removes everything — namespace, all pods, services,
deployments, jobs, configmaps, and secrets.

---

## Key Takeaways

```
apiVersion + kind           → What type of object is this?
metadata.name + namespace   → Unique identity within the cluster
spec.selector               → How Services/Deployments find their Pods
spec.replicas               → How many copies to keep running
spec.template.metadata.labels → Labels applied to every Pod created
containers[].env            → Inline env vars (secrets, exact values)
containers[].envFrom       → ConfigMap as env var source (bulk config)
containers[].volumeMounts  → Where to attach a volume inside the container
volumes[].emptyDir          → Ephemeral storage (lost on pod restart)
Service.spec.type           → ClusterIP (internal) / NodePort (dev) / LoadBalancer (cloud)
Job.spec.backoffLimit       → How many times to retry a failed Job
ConfigMap.data              → Non-sensitive key-value pairs
Secret.stringData           → Sensitive data (base64-encoded at rest)
Kustomize.resources         → Compose multiple dirs into one apply
```

---

## What's Next

Stage 2 adds **namespace isolation, DNS-based service discovery,
and NetworkPolicies** — services can only talk to whitelisted peers.

**Before moving on, make sure you can answer:**
- What happens to a Deployment's Pods when you change the image tag?
- What's the difference between `env:` and `envFrom:`?
- Why does the init Job need a volume to mount the ConfigMap?
- What would break if you set `replicas: 0` on the auth Deployment?