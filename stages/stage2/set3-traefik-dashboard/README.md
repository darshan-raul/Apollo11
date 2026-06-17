---
title: "Stage 2 / Set 3: Traefik Ingress + Dashboard"
description: "Traefik v3 Ingress (host-based routing, NodePort 30443) with the Traefik dashboard exposed at traefik.apollo.local via an IngressRoute to api@internal."
---

# Stage 2 / Set 3 — Traefik Ingress + Dashboard

Builds on **Set 2** by exposing the **Traefik dashboard** at
`http://traefik.apollo.local:30443` using Traefik's built-in
`api@internal` service. Set 2 already routes the 5 user-facing apps
(identity, flight, booking, search, frontend) — Set 3 adds the 6th
route, for the controller's own observability surface.

| | |
|---|---|
| **New concept** | Traefik **dashboard** + **IngressRoute** (CRD) + `api@internal` service |
| **Access pattern** | `open http://traefik.apollo.local:30443` |
| **Controller** | Traefik v3.1 (DaemonSet on control-plane, `--configFile` + `--providers.kubernetescrd`) |
| **DNS** | `/etc/hosts` (6 entries → 127.0.0.1, including `traefik.apollo.local`) |
| **Result** | **27/27 verify checks pass** (25 from Set 2 + 2 dashboard checks) |

The actual *new* work vs Set 2 is **three things**:

1. **`00-traefik-config.yaml`** — a ConfigMap with the Traefik
   *static* config (`traefik.toml`) that enables the API and
   dashboard. Mounted at `/etc/traefik/traefik.toml` in the DaemonSet.
2. **Traefik CRDs** — pulled in step 6 of `apply.sh` from the
   upstream Traefik v3.1 repo. Required for `IngressRoute` (the
   `traefik.io/v1alpha1` CRD kind).
3. **`07-ingress-traefik-dashboard.yaml`** — an `IngressRoute` (CRD)
   that matches `Host("traefik.apollo.local")` and forwards to
   Traefik's built-in `api@internal` service. No extra Service, no
   NodePort, no extra port — Traefik serves its own UI.

Plus the DaemonSet's CLI args change to point at the static config
file and to enable the `kubernetescrd` provider so the
`IngressRoute` is picked up.

---

## Architecture

```
       Browser
         |
         |  HTTP, Host: traefik.apollo.local
         v
   +-----------+        +----------------------+
   |  Traefik  | -----> |   api@internal       |
   |  DS :8000 |        |   (built-in Service) |
   +-----------+        +----------------------+
         |                     |
         |   (also: Host: <svc>.apollo.local  -- Set 2 routes)
         |
   +---------+    +----------+    +---------+
   |identity |    | frontend |    | flight  |  ... (5 ClusterIP Services)
   +---------+    +----------+    +---------+
         ^
         |
   /etc/hosts resolves *.apollo.local + traefik.apollo.local → 127.0.0.1
```

The 6 IngressRoutes / Ingresses (5 user apps + 1 dashboard) all
share the same Traefik pod — the controller multiplexes on the
`Host:` header.

---

## What's new vs Set 2 (file map)

```
k8s/
├── config/                  # (unchanged from Set 2)
│   ├── 00-namespaces.yaml
│   ├── configmap.yaml
│   └── secrets.yaml
├── serviceaccounts/         # (unchanged)
├── networkpolicies/         # reference only — kindnet doesn't enforce
├── apps/                    # (unchanged from Set 2)
├── jobs/                    # (unchanged)
└── ingress/                 # ← mostly Set 2, with 2 new files
    ├── 00-traefik-config.yaml           # NEW — static config (api + dashboard)
    ├── 00-traefik-rbac-and-class.yaml   # (unchanged)
    ├── 01-traefik-daemonset.yaml        # MODIFIED — --configFile + --providers.kubernetescrd
    ├── 01b-traefik-service.yaml
    ├── 02-ingress-frontend.yaml         # (unchanged)
    ├── 03-ingress-identity.yaml         # (unchanged)
    ├── 04-ingress-flight.yaml           # (unchanged)
    ├── 05-ingress-booking.yaml          # (unchanged)
    ├── 06-ingress-search.yaml           # (unchanged)
    └── 07-ingress-traefik-dashboard.yaml # NEW — IngressRoute to api@internal
```

---

## How the dashboard is exposed

`07-ingress-traefik-dashboard.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: kube-system
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`traefik.apollo.local`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
```

Key bits:
- `api@internal` is a **Traefik built-in service** — it routes to
  Traefik's own API handlers (`/api/overview`, `/api/http/routers`,
  `/dashboard/`, etc.). No k8s Service object needed.
- `kind: TraefikService` is required because `api@internal` is a
  Traefik-specific service, not a k8s Service.
- The `traefik.io/v1alpha1` CRD must be installed (step 6 of
  `apply.sh` fetches it from the upstream v3.1 release).

The static config ConfigMap (`00-traefik-config.yaml`) is what
*enables* `api@internal` in the first place — the `[api] dashboard = true`
+ `insecure = true` lines are what flip on the dashboard at
`/dashboard/` and the REST API at `/api/`. Without them, the
IngressRoute would have nothing to route to.

---

## Apply

```bash
cd stages/stage2/set3-traefik-dashboard
./scripts/apply.sh
```

The script (8 steps):
1. Rebuilds the frontend image with Set 3's VITE\_\* URLs
   (same as Set 2 — `apollo.local:30443`)
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts
4. Applies: apps + infra (10 components, all ClusterIP)
5. Applies: 3 init jobs (DB schemas + seed)
6. **NEW: applies Traefik CRDs from upstream v3.1** (needed for
   `IngressRoute`)
7. Applies: Traefik ConfigMap + DaemonSet + RBAC + IngressClass +
   5 Ingresses + 1 IngressRoute (the dashboard)
8. Prints the `/etc/hosts` lines to add

After it finishes, set up the local DNS (now **6** entries instead of 5):

```bash
# Add to /etc/hosts (or use sudo tee):
127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \
            booking.apollo.local search.apollo.local \
            traefik.apollo.local
```

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **27/27 checks pass** (25 from Set 2 + 2 new dashboard checks).

The 2 new checks (last 2 in the script):

| # | Check | What |
|---|---|---|
| 26 | `GET http://traefik.apollo.local:30443/dashboard/` returns 200 | The Traefik dashboard HTML loads |
| 27 | `GET http://traefik.apollo.local:30443/api/overview` returns 200 | The Traefik REST API responds |

Manual smoke test (open in a browser):

```bash
# Traefik dashboard — no auth, lists all routers, services, middlewares
open http://traefik.apollo.local:30443

# App routes still work (regression check on Set 2)
open http://frontend.apollo.local:30443
curl -H 'Host: identity.apollo.local' http://localhost:30443/api/users/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'
```

The dashboard UI shows a live view of:

- **Routers** — every Ingress + IngressRoute, with their rules and
  status
- **Services** — every backend k8s Service, with health
- **Middlewares** — none in this set (Set 2 doesn't use them)
- **HTTP** — per-router request count, latency, status code
  distribution. Refresh after a curl to see counters tick.

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes both `apollo-airlines-*` namespaces and the Traefik
controller + ConfigMap. Leaves the Traefik CRDs in place (they're
cluster-scoped and re-install in seconds; if you want them gone
too, `kubectl delete crd ingressroutes.traefik.io
ingressroutetcps.traefik.io ingressrouteudps.traefik.io
middlewares.traefik.io ...`).

---

## Concepts you should be able to answer

1. **Why does the Traefik dashboard need its own IngressRoute** instead of being reachable directly via the Traefik pod's port? — Set 2's Traefik only listens on `:8000` (the `web` entrypoint). The dashboard handlers (`/dashboard/`, `/api/*`) are registered on the same internal router as the `api@internal` service. By default they're *not exposed* on the `web` entrypoint — the static config has to enable `[api] insecure = true` to expose them.
2. **What's `api@internal`?** — A reserved name Traefik registers for "this controller's own API". The `kind: TraefikService` in the IngressRoute tells Traefik to route to itself rather than to a k8s Service.
3. **Why `--configFile=/etc/traefik/traefik.toml` instead of inline args?** — The static config has nested TOML sections (`[entryPoints.web] address = ":8000"`, `[api] dashboard = true`). TOML is the canonical format and reads cleanly; inline `--entrypoints.web.address=:8000` works for the simple cases but doesn't scale.
4. **Why install Traefik CRDs separately from the DaemonSet?** — The CRDs (`traefik.io/v1alpha1`) are cluster-scoped. The DaemonSet is namespaced. They're independent — the DaemonSet works without the CRDs (it just only sees `Ingress`, not `IngressRoute`). Installing the CRDs first means `07-ingress-traefik-dashboard.yaml` validates when we apply it.
5. **What's the difference between an `Ingress` (k8s standard, set 2) and an `IngressRoute` (Traefik CRD)?** — `Ingress` is portable across ingress controllers but limited in features (no TCP, no middlewares, no per-route TLS). `IngressRoute` is Traefik-specific and supports TCP, middlewares, rate limits, etc. — much richer, but you commit to Traefik. Set 2 uses 5× `Ingress`; Set 3 adds 1× `IngressRoute` because the dashboard is a controller-internal route, not a k8s service.

---

## What's in the dashboard

Open `http://traefik.apollo.local:30443`:

- **Overview** — entrypoint list, router count, service count
- **HTTP → Routers** — the 6 routes Set 3 installs (5 Ingresses + 1 IngressRoute), each showing its rule and backend
- **HTTP → Services** — the 5 backend k8s Services + 1 internal TraefikService (`api@internal`)
- **HTTP → Middlewares** — empty (no middlewares configured in Set 2/3)

The dashboard is **unauthenticated** in this set. In production
you'd add an `auth` middleware (BasicAuth, ForwardAuth, or a JWT
verifier); that's a Stage 8 concern (RBAC + OPA) or earlier if you
want to keep it out of the cluster.

---

## Next set

[Set 4: Traefik Ingress + MetalLB](../set4-metallb-traefik/README.md) —
same dashboard, but the Traefik Service becomes `type: LoadBalancer`
and MetalLB assigns it a real IP. No more `nodePort: 30443` hacks.
