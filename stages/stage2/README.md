---
title: "Stage 2: Guidance — Namespace Isolation, DNS, NetworkPolicies, Ingress"
description: "Split services across 3 namespaces, use FQDN for cross-namespace service discovery, restrict network traffic with NetworkPolicies, and expose the frontend via Traefik Ingress."
---

# Stage 2: Guidance

**Goal:** Understand Kubernetes networking by isolating services
into separate namespaces, using DNS for service discovery, enforcing
network policy to restrict traffic, and exposing the frontend via Ingress.

---

## What You'll Learn

| Concept | File(s) | What It Does |
|---|---|---|
| Namespace isolation | `config/namespace.yaml` | 3 namespaces — infra, apps, ui |
| FQDN service discovery | `config/configmap.yaml` | Cross-namespace calls use `<svc>.<ns>.svc.cluster.local` |
| Headless Services | `infra/**/*-svc-headless.yaml` | DNS returns pod IPs directly (StatefulSet ready) |
| NetworkPolicy | `**/netpol.yaml` | Default-deny + per-service allowlist |
| ServiceAccount | `config/serviceaccount.yaml` | Pod identity per namespace |
| Traefik Ingress | `config/ingress.yaml` | Hostname routing for `frontend.apolloairlines.local` |
| Gateway API | `config/gateway.yaml` | HTTPRoute for `flight.apolloairlines.local` |

---

## Architecture (3 Namespaces)

```
┌────────────────── apollo-airlines-infra ─────────────────────────────┐
│                                                                       │
│  identity-db   (Headless, :5432)  ← allow from apps-ns only         │
│  flight-db     (Headless, :5432)  ← allow from apps-ns only         │
│  booking-db    (Headless, :5432)  ← allow from apps-ns only         │
│  redis         (Headless, :6379) ← allow from apps-ns only         │
│                                                                       │
│  ServiceAccount: apollo11-infra                                       │
│  NetworkPolicy: default-deny + per-service allowlist                 │
└───────────────────────────────────────────────────────────────────────┘
                              ↑ allow from apollo-airlines-apps

┌────────────────── apollo-airlines-apps ────────────────────────────┐
│                                                                       │
│  identity    (ClusterIP, :8080)  ← allow from frontend (ui)        │
│  flight      (ClusterIP, :8081)  ← allow from booking, search        │
│  booking     (ClusterIP, :8082)  ← allow from frontend (ui)         │
│  search      (ClusterIP, :8083) ← allow from frontend (ui)         │
│  notification (ClusterIP, :8084) ← allow from booking               │
│                                                                       │
│  ServiceAccount: apollo11-apps                                       │
│  NetworkPolicy: default-deny + per-service allowlist                 │
│                                                                       │
│  Traefik Ingress: frontend.apolloairlines.local → frontend:3000       │
│  Gateway API: flight.apolloairlines.local → flight:8081               │
└───────────────────────────────────────────────────────────────────────┘
                              ↑ allow from apollo-airlines-ui

┌────────────────── apollo-airlines-ui ─────────────────────────────────┐
│                                                                       │
│  frontend    (ClusterIP, :3000)  ← allow external                   │
│                                                                       │
│  ServiceAccount: apollo11-ui                                         │
│  NetworkPolicy: allow 80/443 inbound                                 │
└───────────────────────────────────────────────────────────────────────┘
```

---

## DNS Resolution

```bash
# From apps namespace — short name works (search path applies)
nslookup identity
# → identity.apollo-airlines-apps.svc.cluster.local

# From ui namespace — must use FQDN
nslookup identity.apollo-airlines-apps.svc.cluster.local
# → resolves to ClusterIP

# Cross-namespace to infra
nslookup identity-db.apollo-airlines-infra.svc.cluster.local
# → resolves (Headless = pod IPs directly for StatefulSets)
```

---

## Deploy

### 1. Build images

```bash
cd /home/darshan/projects/Apollo11/stages/stage2
./scripts/build-images.sh
```

### 2. Apply manifests

```bash
kubectl apply -f k8s/config/
kubectl apply -f k8s/infra/
kubectl apply -f k8s/apps/
kubectl apply -f k8s/ui/
kubectl apply -f k8s/jobs/
```

Or with Kustomize:

```bash
kubectl apply -k k8s/
```

---

## Add to /etc/hosts

```bash
echo "127.0.0.1 frontend.apolloairlines.local" >> /etc/hosts
echo "127.0.0.1 flight.apolloairlines.local" >> /etc/hosts
```

Then access: `http://frontend.apolloairlines.local`

---

## Self-Check

```bash
bash /home/darshan/projects/Apollo11/test/stage2_test.sh
```

---

## Clean Up

```bash
kubectl delete namespace apollo-airlines-infra apollo-airlines-apps apollo-airlines-ui
```

---

## Key Takeaways

```
FQDN format        → <service>.<namespace>.svc.cluster.local
Short name works  → Within same namespace (search path)
FQDN required     → Cross-namespace communication

Headless Service  → clusterIP: None → DNS returns pod IPs directly
                  → StatefulSet pod discovery

NetworkPolicy     → Lives in same namespace as pods it protects
                  → namespaceSelector + podSelector (both must match)
                  → Ingress: first match wins, no match = deny

ServiceAccount    → Pod identity — every pod has one
                  → Referenced explicitly in pod spec
```

---

## What's Next

Stage 3 replaces `emptyDir` volumes with **PersistentVolumeClaims**,
converts infra Deployments to **StatefulSets** with stable pod identity,
and uses **init containers** for DB schema seeding. The frontend stays
accessible via the Traefik Ingress.

**Before moving on:**
1. Why does the infra namespace use Headless Services?
2. What would happen if a NetworkPolicy allowed traffic from the `ui` namespace to `identity-db`?
3. How does a ServiceAccount differ from a Role?