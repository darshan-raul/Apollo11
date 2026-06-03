---
title: "Stage 2: Guidance — Namespace Isolation, DNS, NetworkPolicies"
description: "Split services across 3 namespaces, use FQDN for cross-namespace service discovery, restrict network traffic with NetworkPolicies, and expose services via Ingress and Gateway API."
---

# Stage 2: Guidance

**Goal:** Understand Kubernetes' networking model by isolating services
into separate namespaces, using DNS for service discovery, enforcing
network policy to restrict traffic, and exposing services externally
through Ingress and Gateway API.

---

## What You'll Learn

| Concept | File(s) | What It Does |
|---|---|---|
| Namespace isolation | `config/namespace.yaml` | Scope boundary — cross-ns communication requires explicit DNS |
| CoreDNS / kube-dns | cluster-wide | Translates service FQDNs to ClusterIPs |
| FQDN service discovery | `config/configmap.yaml` | Cross-namespace calls use `<svc>.<ns>.svc.cluster.local` |
| Service types | `**/*-svc.yaml` | ClusterIP (internal), NodePort (simple external), LoadBalancer (cloud), Headless (pod discovery) |
| Ingress | `config/ingress.yaml` | HTTP/HTTPS hostname-based routing to services in apps namespace |
| Gateway API | `config/gateway.yaml` | Next-generation Ingress — typed routes, namespace binding, HTTPRoute |
| NetworkPolicy | `**/netpol.yaml` | Default-deny ingress + allowlist per service |
| ServiceAccount | `config/serviceaccount.yaml` | Pod identity — used by service mesh, RBAC, and NetworkPolicy |
| Pod-to-pod networking | (explained below) | How packets actually flow between pods, nodes, and through CNI |

---

## The Kubernetes Networking Model

Before diving into the manifests, understand how networking works in Kubernetes.
Every concept in this stage — DNS, Services, Ingress, NetworkPolicy — is built
on these foundations.

### Reality 1: Every pod gets its own network namespace

Each pod has its own Linux network namespace: its own IP address, routing table,
and `eth0` interface inside the pod. Pods cannot see or bind to each other's
interfaces directly.

```
Pod A (10.244.1.5)                          Pod B (10.244.2.8)
┌──────────────────────┐              ┌──────────────────────┐
│ eth0                 │              │ eth0                 │
│ 10.244.1.5           │              │ 10.244.2.8           │
│                      │              │                      │
│ ┌──────────────────┐ │   CNI bridge │ ┌──────────────────┐ │
│ │ your application │ │◀────────────▶│ │ your application │ │
│ │ binds to :8080   │ │   (cni0)     │ │ binds to :8081   │ │
│ └──────────────────┘ │              └──────────────────────┘
└──────────────────────┘
```

### Reality 2: Pods communicate over a virtual bridge created by the CNI plugin

The CNI plugin (Calico, Weave, Flannel, Cilium) creates:
- A **veth pair**: `eth0` inside the pod ↔ `veth-xxx` on the node
- A **bridge** (`cni0`) on the node that connects all veth pairs
- Pod IPs from the **pod CIDR** range (e.g. `10.244.0.0/16`)

**Same node:** pod → veth → bridge → veth → target pod (direct, no encapsulation)
**Different node:** pod → bridge → node routing table → encapsulation tunnel
(VXLAN/GRE) → remote node's tunl0 → bridge → target pod

### Reality 3: Services get a stable virtual IP (ClusterIP) managed by iptables/IPVS

A Service gets a **ClusterIP** (e.g. `10.96.0.100`) that never appears on any
real network interface. It's a **Virtual IP (VIP)** managed by iptables/IPVS
rules on every node:

```
# Simplified iptables rule (every node has identical rules)
-A KUBE-SERVICES -d 10.96.0.100/32 -p tcp --dport 8080 \
    -j KUBE-SVC-NWP5WRQ7VCSGDZTD  (→ randomly selects a backend pod)
```

When a pod connects to `10.96.0.100:8080`, iptables DNATs the destination to
a real backend pod IP (e.g. `10.244.2.15:8081`). The client pod never sees
the backend pod's real IP — to the client it looks like a local connection.

### Reality 4: kube-dns (CoreDNS) translates service FQDNs to ClusterIPs

Every Service gets an A record added to CoreDNS:
```
auth.apollo11-apps.svc.cluster.local → 10.96.0.150
```

Pods query `10.96.0.10` (the kube-dns Service IP). The `/etc/resolv.conf`
in every pod contains the nameserver and a search path:

```
nameserver 10.96.0.10
search apollo11-apps.svc.cluster.local apollo11.svc.cluster.local
       svc.cluster.local cluster.local
```

This is why `auth` resolves within `apollo11-apps` but NOT from
`apollo11-ui` — the search path only contains the destination pod's
own namespace suffixes.

---

### Service Types: ClusterIP, NodePort, LoadBalancer, Headless

A Service in Kubernetes is a stable network endpoint. There are four types:

| Type | Example | Use Case |
|---|---|---|
| **ClusterIP** (default) | `10.96.0.150:8080` | Internal-only — pods within the cluster |
| **NodePort** | `:30080` on every node | Simple external access — bypasses Ingress |
| **LoadBalancer** | cloud LB assigns external IP | Production — integrates with cloud infra |
| **Headless** | `spec.clusterIP: None` | Direct pod-to-pod discovery (StatefulSets) |

```
ClusterIP — internal virtual IP, managed by iptables/IPVS
  Pod → ClusterIP → iptables DNAT → backend pod

NodePort — exposes a port on EVERY node's external interface
  External → node:30080 → Service ClusterIP → iptables DNAT → backend pod
  Note: NodePort traffic goes through kube-proxy's NodePort rules,
  which are separate from pod-level NetworkPolicy.
  NodePort bypasses pod Ingress rules! (external → node → kube-proxy → pod directly)

LoadBalancer — cloud controller provisions an external LB
  External → cloud LB → backend Service → iptables → backend pod

Headless — no ClusterIP, DNS returns pod IPs directly
  DNS query for catalog.apollo11-apps.svc.cluster.local
  → returns pod IPs: [10.244.1.10, 10.244.1.11, 10.244.1.12]
  → client does DNS round-robin directly to pods
  → used by StatefulSets for stable pod identity
```

In stage 2:
- All infra + app services use **ClusterIP** (internal only)
- Frontend uses **NodePort** (port 30080) for simple external access
- StatefulSets in stage 3 will use **Headless** for database pod discovery
- **LoadBalancer** not used here (requires cloud or MetalLB)

---

### Ingress and Gateway API

**Ingress** is the Kubernetes resource for HTTP/HTTPS hostname-based routing
to Services. It sits in front of your ClusterIP/NodePort services and terminates
HTTP traffic, routing it by host + path rules.

```
External client
    │
    │ https://api.apollo11.local/
    ▼
Ingress (api.apollo11.local → auth:8080)
    │         (catalog.apollo11.local → catalog:8081)
    ▼
ClusterIP Service auth (10.96.0.150 → backend pods)
    │
    ▼
auth pod (10.244.1.5)
```

**Why Ingress in stage 2?** The frontend currently uses NodePort (`:30080`).
Ingress gives you hostname-based routing with TLS termination — closer to
production. We use a simple Ingress for `api.apollo11.local` → auth service.

**Gateway API** is the next-generation Ingress (正式的, not deprecated).
It uses different resources:

| Ingress (legacy) | Gateway API (new) |
|---|---|
| `kind: Ingress` | `kind: Gateway` (the actual listener) |
| Single ingress object | `Gateway` + `HTTPRoute` (bound to namespace) |
| Annotations for features | Native field definitions (typed) |
| No namespace binding concept | `HTTPRoute` can reference Gateway across namespaces |

Stage 2 deploys **both** — Traefik as the legacy Ingress controller,
and **Envoy Gateway** (Gateway API) for the next-generation model.

```
Legacy Ingress (Traefik):
  api.apollo11.local → auth service (port 8080)
  catalog.apollo11.local → catalog service (port 8081)

Gateway API flow (Envoy):
  Gateway (apollo11-apps/apollo11-gateway) — port 80 listener
    HTTPRoute (apollo11-apps/catalog-route)
      → parentRefs: apollo11-gateway (sectionName: http)
      → host: catalog.apollo11.local
      → rules: / → catalog:8081
```

---

### ServiceAccount: Pod Identity

Every pod runs as a ServiceAccount. By default, pods use the `default`
ServiceAccount in their namespace (auto-created, no secrets).

ServiceAccounts provide **identity** — used by:
- **RBAC** (RoleBinding/ClusterRoleBinding) to grant pod permissions
- **NetworkPolicy** (future: pod identity-based policy with Cilium)
- **Service mesh** (e.g. Istio uses ServiceAccount to mTLS identity)
- **External secrets** (AWS IAM roles for service accounts)

```
Pod → mounted token at /var/run/secrets/kubernetes.io/serviceaccount/
     → contains namespace, ServiceAccount name, JWT token
     → kube-apiserver validates token
```

In stage 2, each namespace gets a named ServiceAccount (`infra`, `apps`, `ui`).
The manifests reference these explicitly to demonstrate the pattern:

```yaml
spec:
  serviceAccountName: apollo11-apps
```

---

### Worked Example: Full packet path (DNS → Service → Pod)

When your auth pod calls `http://catalog.apollo11-apps.svc.cluster.local:8081`:

```
1. App calls: catalog.apollo11-apps.svc.cluster.local:8081
   ↓
2. libc reads /etc/resolv.conf → nameserver 10.96.0.10
3. DNS query → kube-dns (CoreDNS)
4. CoreDNS looks up: catalog.apollo11-apps.svc.cluster.local
   → finds Service → returns ClusterIP 10.96.0.180
5. Pod sends packet to 10.96.0.180:8081
6. iptables on node matches: -d 10.96.0.180/32 --dport 8081
   → DNATs to one catalog backend pod (e.g. 10.244.2.15:8081)
7. Same node? bridge delivers directly.
   Cross node? routing table → VXLAN/GRE encapsulation → target node
8. catalog pod's eth0 receives the packet (apps thinks it's direct)
```

---

## Architecture (3 Namespaces)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Cluster-wide: CoreDNS (kube-dns) — 10.96.0.10                            │
│  Resolves: auth.apollo11-apps.svc.cluster.local → ClusterIP 10.96.x.x     │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────── apollo11-infra ──────────────────────────────────────┐
│                                                                         │
│  auth-postgres      (ClusterIP:5432)  ← allow from [auth] in apps-ns   │
│  catalog-postgres   (ClusterIP:5432)  ← allow from [catalog] in apps-ns│
│  circulation-postgres (ClusterIP:5432) ← allow from [circulation]      │
│  catalog-redis      (ClusterIP:6379)   ← allow from [catalog]          │
│  notification-redis (ClusterIP:6380)  ← allow from [notification]     │
│                                                                         │
│  NetworkPolicy: default-deny ingress, + per-service allowlist          │
│  ServiceAccount: apollo11-infra                                        │
└─────────────────────────────────────────────────────────────────────────┘

                        ↑ allow from apollo11-apps
                        │ (namespaceSelector: name=apollo11-apps)

┌──────────────────── apollo11-apps ──────────────────────────────────────┐
│                                                                         │
│  auth          (ClusterIP:8080)  ← allow from [frontend] in ui-ns     │
│  catalog       (ClusterIP:8081)  ← allow from [frontend] in ui-ns     │
│  circulation   (ClusterIP:8082)  ← allow from [frontend] in ui-ns    │
│  notification  (ClusterIP:8083)  ← allow from [frontend] in ui-ns    │
│  fines         (ClusterIP:8084)  ← allow from [frontend] in ui-ns     │
│                                                                         │
│  NetworkPolicy: default-deny ingress, + allow from frontend            │
│  ServiceAccount: apollo11-apps                                        │
│                                                                         │
│  Ingress (Traefik): api.apollo11.local → auth:8080              │
│  Gateway (Envoy): apollo11-gateway + catalog-route → catalog    │
└─────────────────────────────────────────────────────────────────────────┘

                        ↑ allow from apollo11-ui
                        │ (namespaceSelector: name=apollo11-ui)

┌──────────────────── apollo11-ui ─────────────────────────────────────────┐
│                                                                         │
│  frontend   (NodePort:30080)  ← public-facing, no ingress restrictions │
│  /health, /api/auth, /api/catalog, /api/circulation, /api/fines        │
│                                                                         │
│  Makes FQDN outbound calls to all apollo11-apps services              │
│  ServiceAccount: apollo11-ui                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### DNS Resolution in Action

```bash
# From a pod in apollo11-apps: short name works (search path applies)
nslookup auth
# Name:   auth.apollo11-apps.svc.cluster.local
# Address: 10.96.0.150

# From a pod in apollo11-ui: short name FAILS (wrong search path)
nslookup auth
# NXDOMAIN — must use FQDN

# Cross-namespace DNS always works with FQDN
nslookup auth.apollo11-apps.svc.cluster.local
# Address: 10.96.0.150

# Cross-namespace to infra works too
nslookup auth-postgres.apollo11-infra.svc.cluster.local
# Address: 10.96.0.101
```

---

## Manifest Anatomy — Namespaces

`config/namespace.yaml` (all 3 namespaces in one file):

```yaml
# ── Infrastructure namespace ─────────────────────────────────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: apollo11-infra
  labels:
    name: apollo11-infra                  # ← used by namespaceSelector in netpols
    app.kubernetes.io/component: infrastructure
    kubernetes.io/metadata.name: apollo11-infra  # ← well-known label, always present

---
# ── Applications namespace ──────────────────────────────────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: apollo11-apps
  labels:
    name: apollo11-apps
    app.kubernetes.io/component: applications
    kubernetes.io/metadata.name: apollo11-apps

---
# ── UI namespace ──────────────────────────────────────────────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: apollo11-ui
  labels:
    name: apollo11-ui
    app.kubernetes.io/component: ui
    kubernetes.io/metadata.name: apollo11-ui
```

> **Why `name: apollo11-xxx` as a label?** The NetworkPolicy's
> `namespaceSelector: matchLabels: name: apollo11-apps` relies on the
> namespace having that label. Kubernetes does NOT automatically add the
> namespace name as a label — you must add it explicitly. We also include
> `kubernetes.io/metadata.name` which is the canonical well-known label.

---

## Manifest Anatomy — ServiceAccount

`config/serviceaccount.yaml` (one per namespace):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: apollo11-apps
  namespace: apollo11-apps
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: apollo11-infra
  namespace: apollo11-infra
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: apollo11-ui
  namespace: apollo11-ui
```

In each Deployment, reference the ServiceAccount:

```yaml
spec:
  serviceAccountName: apollo11-apps   # in the pod template spec
```

---

## Manifest Anatomy — ConfigMap (FQDN Service URLs)

`config/configmap.yaml` (in `apollo11-apps` namespace):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: apollo11-config
  namespace: apollo11-apps

data:
  # FQDN format: <service>.<namespace>.svc.cluster.local:<port>
  AUTH_SERVICE_URL:        "http://auth.apollo11-apps.svc.cluster.local:8080"
  CATALOG_SERVICE_URL:      "http://catalog.apollo11-apps.svc.cluster.local:8081"
  CIRCULATION_SERVICE_URL: "http://circulation.apollo11-apps.svc.cluster.local:8082"
  NOTIFICATION_SERVICE_URL: "http://notification.apollo11-apps.svc.cluster.local:8083"
  FINES_SERVICE_URL:        "http://fines.apollo11-apps.svc.cluster.local:8084"

  # Cross-namespace: infra service URLs include the namespace
  CATALOG_REDIS_URL:  "redis://catalog-redis.apollo11-infra.svc.cluster.local:6379"
  CATALOG_DB_HOST:    "catalog-postgres.apollo11-infra.svc.cluster.local"
```

---

## Manifest Anatomy — NetworkPolicy

`infra/postgres/auth-postgres-netpol.yaml` (lives in `apollo11-infra`):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: auth-postgres-allow-specific
  namespace: apollo11-infra        # ← NetworkPolicy lives in the SAME namespace
                                   #   as the pods it protects
spec:
  podSelector:
    matchLabels:
      app: auth-postgres           # ← applies to all pods with label app=auth-postgres

  policyTypes:
    - Ingress                      # ← controls inbound traffic only

  ingress:
    # Allow inbound ONLY from auth pods in apollo11-apps namespace
    - from:
        - namespaceSelector:        # ← first: match by namespace label
            matchLabels:
              name: apollo11-apps  # ← namespace must have this label!
          podSelector:              # ← second: match by pod label within that namespace
            matchLabels:
              app: auth             # ← only the auth pod specifically
```

**Key distinction:**
- `namespaceSelector` — matches the **namespace** the traffic comes FROM
- `podSelector` — matches the **pods** within that namespace

Both must match for the rule to allow traffic.

```
packet from auth pod (apollo11-apps, app=auth) → auth-postgres pod
  namespaceSelector: name=apollo11-apps?  YES → podSelector: app=auth? YES → ALLOWED

packet from catalog pod (apollo11-apps, app=catalog) → auth-postgres pod
  namespaceSelector: name=apollo11-apps?  YES → podSelector: app=auth? NO → DENIED

packet from frontend pod (apollo11-ui, app=frontend) → auth-postgres pod
  namespaceSelector: name=apollo11-apps?  NO → DENIED
```

---

## Manifest Anatomy — Ingress (Legacy)

`config/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apollo11-ingress
  namespace: apollo11-apps
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: traefik       # ← Traefik is the Ingress controller (install first)
  rules:
    # Route: api.apollo11.local → auth service
    - host: api.apollo11.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: auth
                port:
                  number: 8080

    # Route: catalog.apollo11.local → catalog service
    - host: catalog.apollo11.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: catalog
                port:
                  number: 8081
```

The Ingress controller (nginx-ingress running in the cluster) watches for
Ingress resources and configures the proxy accordingly.

---

## Manifest Anatomy — Gateway API (New)

`config/gateway.yaml`:

```yaml
# Gateway — the listener resource (owns port 80)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-gateway
  namespace: apollo11-apps
spec:
  gatewayClassName: envoy           # ← Envoy Gateway is the controller (install first)
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: same                # ← HTTPRoute must be in the same namespace
---
# HTTPRoute — defines routing rules (bound to the Gateway)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: catalog-route
  namespace: apollo11-apps
spec:
  parentRefs:
    - name: gateway-gateway
      namespace: apollo11-apps
      sectionName: http
  hostnames:
    - catalog.apollo11.local
  rules:
    - backend:
        - name: catalog
          port: 8081
          weight: 1
```

Gateway API separates concerns: `Gateway` is the infrastructure (listening on
port 80), `HTTPRoute` is the routing rule. Multiple teams can own their own
HTTPRoutes while a platform team owns the Gateway.

---

## Manifest Anatomy — Deployment (cross-namespace env)

`apps/catalog/catalog-dep.yaml` — referencing infra services via FQDN:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: apollo11-apps
spec:
  serviceAccountName: apollo11-apps    # ← uses the apps ServiceAccount
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
        - name: catalog
          image: apollo11/catalog:latest
          ports:
            - containerPort: 8081
          env:
            # Cross-namespace: must use FQDN
            - name: DATABASE_URL
              value: "postgresql://postgres:***@catalog-postgres.apollo11-infra.svc.cluster.local:5432/catalog"
            - name: REDIS_URL
              value: "redis://catalog-redis.apollo11-infra.svc.cluster.local:6379"
          envFrom:
            - configMapRef:
                name: apollo11-config
```

---

## Manifest Structure (apply in this order)

```
k8s/
├── config/
│   ├── namespace.yaml       # 1. All 3 namespaces
│   ├── serviceaccount.yaml  # 2. ServiceAccounts per namespace
│   ├── configmap.yaml       # 3. FQDN service URLs
│   ├── secrets.yaml         # 4. Secrets (shared across namespaces)
│   ├── ingress.yaml         # 5. Legacy Ingress (HTTP routing)
│   └── gateway.yaml         # 6. Gateway API (Gateway + HTTPRoute)
├── infra/                   # 7. Postgres + Redis in apollo11-infra
│   ├── postgres/            #   (auth/catalog/circulation) × (dep + svc + netpol)
│   └── redis/               #   (catalog/notification) × (dep + svc + netpol)
├── apps/                    # 8. Business logic in apollo11-apps
│   ├── auth/                #   (auth/catalog/circulation/notification/fines)
│   │   ├── auth-dep.yaml   #     dep + svc + netpol
│   │   ├── auth-svc.yaml
│   │   └── auth-netpol.yaml
│   └── ...
├── ui/                      # 9. Frontend in apollo11-ui
│   └── frontend/
│       ├── frontend-dep.yaml
│       ├── frontend-svc.yaml
│       └── frontend-netpol.yaml
└── jobs/                    # 10. DB init jobs in apollo11-apps
    └── init-*.yaml
```

---

## Deploy

### 1. Build the container images

```bash
cd /home/darshan/projects/Apollo11/stages/stage2
./scripts/build-images.sh
```

### 2. Apply manifests in dependency order

```bash
# Layer 1: All 3 namespaces
kubectl apply -f k8s/config/namespace.yaml

# Layer 2: ServiceAccounts
kubectl apply -f k8s/config/serviceaccount.yaml

# Layer 3: ConfigMap and Secrets
kubectl apply -f k8s/config/configmap.yaml
kubectl apply -f k8s/config/secrets.yaml

# Layer 4: Ingress + Gateway (before apps — Ingress controller watches these)
kubectl apply -f k8s/config/ingress.yaml
kubectl apply -f k8s/config/gateway.yaml

# Layer 5: Infrastructure (in apollo11-infra)
kubectl apply -f k8s/infra/postgres/
kubectl apply -f k8s/infra/redis/

# Layer 6: Application services (in apollo11-apps)
kubectl apply -f k8s/apps/auth/
kubectl apply -f k8s/apps/catalog/
kubectl apply -f k8s/apps/circulation/
kubectl apply -f k8s/apps/notification/
kubectl apply -f k8s/apps/fines/

# Layer 7: UI service (in apollo11-ui)
kubectl apply -f k8s/ui/frontend/

# Layer 8: Init jobs (in apollo11-apps, after DBs are running)
kubectl apply -f k8s/jobs/
```

### 3. Watch pods across all 3 namespaces

```bash
kubectl get pods -n apollo11-infra -w &
kubectl get pods -n apollo11-apps -w &
kubectl get pods -n apollo11-ui -w &

# Or with stern (all namespaces)
stern . -n apollo11-infra -n apollo11-apps -n apollo11-ui
```

---

## Access the Services

**Frontend via NodePort:**
```
http://localhost:30080
```

**Frontend via Ingress (after adding /etc/hosts entry):**
```
# Add to /etc/hosts:
127.0.0.1 api.apollo11.local catalog.apollo11.local

# Then access via Ingress:
curl http://api.apollo11.local/
```

**Test DNS resolution from a debug pod:**

```bash
kubectl run dnsutils --image=tutum/dnsutils --rm -it -- sh

# Inside the pod:
nslookup auth.apollo11-apps.svc.cluster.local
nslookup auth-postgres.apollo11-infra.svc.cluster.local

# Short name (should fail from wrong namespace):
nslookup auth   # NXDOMAIN in apollo11-ui
```

**Port-forward individual services:**

```bash
# Auth in apollo11-apps
kubectl port-forward -n apollo11-apps svc/auth 8080:8080
curl http://localhost:8080/health

# Frontend in apollo11-ui
kubectl port-forward -n apollo11-ui svc/frontend 3000:80
curl http://localhost:3000/health
```

**Important — NodePort vs Ingress:**
- **NodePort** traffic bypasses pod-level NetworkPolicy ingress rules.
  External traffic → node:30080 → kube-proxy → pod directly (node-level)
- **Ingress** traffic is routed through the Ingress controller pod,
  which is subject to NetworkPolicy. Use Ingress for production;
  use NodePort only for simple dev/testing.

---

## Self-Check

Run the automated test script:

```bash
cd /home/darshan/projects/Apollo11
bash test/stage2_test.sh
```

The script verifies:
- All 3 namespaces exist
- All 3 ServiceAccounts exist
- All 11 Deployments across all namespaces are Ready
- All 11 Services exist with correct ports
- All 10 NetworkPolicies exist with correct Ingress rules
- Ingress and Gateway resources are valid
- Init Jobs completed successfully
- ConfigMap has correct FQDN service URLs
- DNS resolution works (cross-namespace FQDN, same-namespace short name)

---

## Clean Up

Delete in reverse dependency order:

```bash
kubectl delete -f k8s/jobs/
kubectl delete -f k8s/ui/frontend/
kubectl delete -f k8s/apps/fines/
kubectl delete -f k8s/apps/notification/
kubectl delete -f k8s/apps/circulation/
kubectl delete -f k8s/apps/catalog/
kubectl delete -f k8s/apps/auth/
kubectl delete -f k8s/infra/redis/
kubectl delete -f k8s/infra/postgres/
kubectl delete -f k8s/config/ingress.yaml
kubectl delete -f k8s/config/gateway.yaml
kubectl delete -f k8s/config/serviceaccount.yaml
kubectl delete -f k8s/config/namespace.yaml
```

Or delete all 3 namespaces at once:

```bash
kubectl delete namespace apollo11-infra apollo11-apps apollo11-ui
```

---

## Key Takeaways

```
Pod networking     → Each pod has its own network namespace (unique IP)
                     Pods communicate via CNI bridge — no NAT between pods

CNI plugin         → Creates veth pairs, bridges pods to node network
                     Assigns pod IPs from pod CIDR range

Service (ClusterIP)→ Stable virtual IP — never appears on any real interface
                     Managed by iptables/IPVS on every node
                     DNATs to backend pod IPs (load-balanced)

NodePort           → Exposes port on EVERY node's external interface
                     Bypasses pod-level NetworkPolicy ingress rules
                     Use only for dev/testing

LoadBalancer       → Cloud controller provisions external LB
                     Production-grade external access

Headless Service   → No ClusterIP, DNS returns pod IPs directly
                     Used by StatefulSets for pod-to-pod discovery

kube-dns (CoreDNS) → Translates FQDN → ClusterIP
                     Pod /etc/resolv.conf has nameserver + search suffixes

FQDN format        → <service>.<namespace>.svc.cluster.local
                     svc.cluster.local is the visible cluster suffix

Short name works   → Within same namespace (search path appends <ns>.svc...)
FQDN required      → Cross-namespace communication

Ingress            → HTTP/HTTPS hostname+path routing to backends
                     Ingress controller watches Ingress resources

Gateway API        → Next-generation: Gateway (listener) + HTTPRoute (rules)
                     Separates infra ownership from app routing ownership

NetworkPolicy      → Lives in same namespace as the pods it protects
                     namespaceSelector: match by namespace label
                     podSelector: match by pod label within that namespace
                     Ingress: first match wins, no match = deny
                     NodePort traffic bypasses pod-level ingress rules

ServiceAccount     → Pod identity — used by RBAC, service mesh, NetworkPolicy
                     Every pod has one (defaults to namespace's `default` SA)
                     Mounted at /var/run/secrets/kubernetes.io/serviceaccount/
```

---

## What's Next

Stage 3 introduces **persistent storage** — PersistentVolumeClaims,
StatefulSets, and init containers for database seeding. The `emptyDir`
volumes from stages 1 and 2 are replaced with durable storage so data
survives pod restarts. The frontend's NodePort is replaced with a proper
Ingress for external access.

**Before moving on, make sure you can answer:**

1. What does the CNI plugin create when a pod starts? What's a veth pair?
2. How does a Service differ from a Deployment in terms of networking?
3. Why does `auth.apollo11-apps.svc.cluster.local` resolve but `auth` doesn't
   from the `apollo11-ui` namespace?
4. What happens to traffic that doesn't match any NetworkPolicy ingress rule?
5. What's the difference between `podSelector` and `namespaceSelector` in a
   NetworkPolicy rule?
6. Why is `namespaceSelector: name: apollo11-apps` only guaranteed to work
   if the namespace has that label explicitly set?
7. What's the difference between ClusterIP, NodePort, LoadBalancer, and Headless
   Service types? When would you use each?
8. What does a ServiceAccount provide a pod? Where is its token mounted?
9. What's the difference between legacy Ingress and Gateway API HTTPRoute?
   Why does Gateway API separate Gateway from HTTPRoute?
10. Why does NodePort traffic bypass pod-level NetworkPolicy ingress rules,
    but Ingress traffic goes through the Ingress controller pod?