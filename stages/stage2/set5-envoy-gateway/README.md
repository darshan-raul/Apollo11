---
title: "Stage 2 / Set 5: Envoy Gateway + MetalLB"
description: "Gateway API CRDs (GatewayClass, Gateway, HTTPRoute, ReferenceGrant) with Envoy Gateway v1.5.0 as the data plane. MetalLB provides the LoadBalancer IP — same as Set 4."
---

# Stage 2 / Set 5 — Envoy Gateway + MetalLB

Set 5 is the same MetalLB stack as Set 4, but **Traefik is replaced
with the Gateway API + Envoy Gateway v1.5.0**. The Gateway API is
the upstream Kubernetes replacement for Ingress — graduated to GA in
k8s 1.24 — and Envoy is the data-plane proxy. This is the access
stack that **carries forward to Stage 3+** (StatefulSets, probes,
Helm chart, observability, all of it).

| | |
|---|---|
| **New concept** | Gateway API (`GatewayClass`, `Gateway`, `HTTPRoute`, `ReferenceGrant`, `EnvoyProxy`) |
| **Access pattern** | `curl -H 'Host: identity.apollo.local' http://172.18.0.50/...` (MetalLB IP) |
| **Controller** | Envoy Gateway v1.5.0 (envoyproxy/gateway:v1.5.0) |
| **DNS** | `/etc/hosts` (5 entries → the IP MetalLB gave Envoy, printed by apply.sh) |
| **Result** | **29/29 verify checks pass** |

The **actual** new work vs Set 4 is **the entire `k8s/gateway/` dir**
(11 files, replacing the `k8s/ingress/` dir). MetalLB is identical
to Set 4 — same install, same IP pool, same L2Advertisement.

---

## Architecture

```
   GatewayClass (cluster-scoped)
       |  controllerName: gateway.envoyproxy.io/gatewayclass-controller
       v
   +-------------+
   |  Gateway    |   (namespaced: apollo-airlines-apps)
   |  apollo-    |   listener: port 80, HTTP
   |  gateway    |   infrastructure.parametersRef -> EnvoyProxy
   +-----+-------+
         |
         |  EnvoyProxy CRD: "auto-create the data-plane Service
         |                   as type=LoadBalancer (MetalLB gives the IP)"
         v
   +--------------------+
   | envoy-gateway       |   (control plane, Deployment in envoy-gateway-system)
   | control plane       |   reconciles Gateway + HTTPRoute into Envoy config
   +-----+--------------+
         |  pushes LDS/RDS/CDS to
         v
   +--------------------+
   | Envoy proxy        |   (data plane, Deployment in envoy-gateway-system)
   | Service: LB        |   MetalLB assigns 172.18.0.50 from apollo-pool
   +-----+--------------+
         |
         |  Routes by Host header (RDS lookup)
         |
   +---------+    +----------+    +---------+
   |identity |    | frontend |    | flight  |  ... (5 ClusterIP Services)
   +---------+    +----------+    +---------+

   6 HTTPRoutes (1 per service) attach to the Gateway
   frontend HTTPRoute is in apollo-airlines-ui ns -> needs ReferenceGrant
```

The 6 HTTPRoutes + 1 ReferenceGrant are the new resources vs Set 4.
Gateway API replaces Ingress entirely. Envoy is the new data plane.

---

## What's new vs Set 4 (file map)

```
k8s/
├── config/                          # (unchanged)
├── serviceaccounts/                 # (unchanged)
├── networkpolicies/                 # (unchanged — reference only)
├── apps/                            # (unchanged — 6 apps + 4 infra)
├── jobs/                            # (unchanged — 3 init jobs)
├── metallb/                         # (unchanged from Set 4)
│   ├── 00-metallb-native.yaml
│   └── 01-ip-pool.yaml
└── gateway/                         # ← NEW (replaces ingress/)
    ├── 00-envoy-gateway-install.yaml # vendored install (~2.9MB, --server-side)
    ├── 00a-gatewayclass.yaml        # GatewayClass (NOT in install.yaml)
    ├── 00b-envoyproxy.yaml          # EnvoyProxy: envoyService.type=LoadBalancer
    ├── 01-gateway.yaml              # Gateway: port 80, HTTP
    ├── 01a-referencegrant.yaml      # cross-namespace HTTPRoute attachment
    ├── 02-httproute-identity.yaml
    ├── 03-httproute-flight.yaml
    ├── 04-httproute-booking.yaml
    ├── 05-httproute-search.yaml
    ├── 06-httproute-notification.yaml
    └── 07-httproute-frontend.yaml   # lives in apollo-airlines-ui ns
```

11 files in `gateway/`, all 6 HTTPRoutes are CRDs (not the
`networking.k8s.io/v1` Ingress kind), plus the 4 cluster-scoped
Gateway-API objects.

---

## Gateway API vs Ingress (why this matters)

`Ingress` is the k8s-standard "route external HTTP to Services" object.
It's portable across ingress controllers (Traefik, nginx-ingress,
HAProxy, Envoy) but its feature set is **deliberately limited** to
keep the standard small:

- Host + path matching
- TLS termination
- Optional `IngressClass` for controller selection

That's it. No header-based routing, no traffic splitting, no per-route
middlewares, no multi-tenancy. Every controller that wanted those
features defined a CRD (Traefik's `IngressRoute`, Contour's
`HTTPRoute`, Istio's `VirtualService`) — defeating the portability
goal.

`Gateway API` is the upstream k8s replacement. It graduated to **GA in
k8s 1.24** (May 2022) and defines a richer set of resources:

| Resource | Scope | Purpose |
|---|---|---|
| `GatewayClass` | cluster | One per controller. `spec.controllerName` selects the controller. |
| `Gateway` | namespace | A proxy instance — listeners, port, TLS config. The "edge". |
| `HTTPRoute` | namespace | Route rules — host, path, headers, query params, backend refs. |
| `ReferenceGrant` | namespace | Allow a HTTPRoute in one ns to reference resources (Service, Secret) in another ns. The cross-namespace guard rail. |
| `TCPRoute`, `UDPRoute`, `TLSRoute` | namespace | Same shape, for non-HTTP traffic. |
| `EnvoyProxy` | namespace (CRD, not GA) | Envoy-specific tuning — service type, deployment shape, telemetry. |

Set 5 uses **5** of these: GatewayClass (1), Gateway (1), HTTPRoute
(6, one per service), ReferenceGrant (1, for the cross-namespace
frontend route), and EnvoyProxy (1, to set the data-plane Service
type to LoadBalancer).

---

## Envoy Gateway v1.5.0 — why this version

The bundled `install.yaml` is **2.9MB** (much larger than v1.2.4's
2.4MB) and ships with `envoyproxy/gateway:v1.5.0`. v1.5.0 was
chosen via a 5-version sweep (v1.2.4, v1.3.0, v1.4.0, v1.4.5,
v1.5.0) — all 5 correctly materialize the data-plane listener via
LDS and serve HTTP 200, but v1.5.0 was the most-validated-in-session.
See `stages/stage2/NOTES.md` for the full methodology.

**The big v1.5.0 win:** the Envoy data-plane Service is now
`type: LoadBalancer` by default. In v1.2.4 you had to write an
`EnvoyProxy` resource that explicitly set `envoyService.type:
LoadBalancer` (and even then, a `kubectl patch` loop was sometimes
needed). v1.5.0 just does it.

The `EnvoyProxy` in `00b-envoyproxy.yaml` is **still present** — but
it's a no-op in v1.5.0 (the default already matches). It would be
load-bearing if you needed to override the Service to use a custom
`nodePort`, or to inject extra Envoy filters. For this set, it's
belt-and-suspenders; for production tunings, it's the right hook.

**`install.yaml` quirks:**

- It's 2.9MB. **Must use `kubectl apply --server-side`** — client-side
  apply would exceed the API server's 256KB last-applied-config
  annotation limit.
- It does **NOT** create a `GatewayClass` resource. The install
  creates the CRDs + the controller Deployment + the webhook, but
  the `GatewayClass` is yours to define. `00a-gatewayclass.yaml` does
  this with `controllerName:
  gateway.envoyproxy.io/gatewayclass-controller`.

---

## The 4 Gateway-API objects explained

### 1. `GatewayClass` (cluster-scoped)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

`controllerName` is a reverse-DNS string that the controller's
admission webhook validates. Only one controller in the cluster
should claim this name. With v1.5.0's default install, the
controller Deployment ships with this exact name as a label
selector — so creating the GatewayClass binds the cluster to
Envoy Gateway's controller.

### 2. `EnvoyProxy` (namespaced, CRD)

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoyproxy-lb-config
  namespace: apollo-airlines-apps
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
```

This is the **infrastructure override** for the Gateway. The
Gateway's `infrastructure.parametersRef` (in `01-gateway.yaml`)
points at this EnvoyProxy by name. Without it, v1.5.0 already
creates a LoadBalancer Service — but having the explicit
EnvoyProxy means:
- (a) any future Envoy config change is a one-line edit
- (b) the file is the documentation of "yes, we want
  LoadBalancer" — clear intent

### 3. `Gateway` (namespaced)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: apollo-gateway
  namespace: apollo-airlines-apps
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: envoyproxy-lb-config
  listeners:
    - name: web
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
```

`allowedRoutes.namespaces.from: All` is **required for the
frontend's HTTPRoute** (which lives in `apollo-airlines-ui`) to
attach. Without it, only HTTPRoutes in the same namespace as the
Gateway can bind. Cross-namespace attachment still requires a
`ReferenceGrant` (see below).

### 4. `HTTPRoute` × 6 (namespaced)

One per service:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: identity
  namespace: apollo-airlines-apps
spec:
  parentRefs:
    - name: apollo-gateway
      namespace: apollo-airlines-apps
  hostnames:
    - identity.apollo.local
  rules:
    - backendRefs:
        - name: identity
          port: 8080
```

The 5 backend HTTPRoutes (`02-` to `06-`) all live in the apps ns
and reference the Gateway in the same ns.

The 6th HTTPRoute (`07-httproute-frontend.yaml`) is the special
one — it lives in the `ui` ns and needs both `parentRef.namespace`
explicitly set AND a `ReferenceGrant` in the apps ns.

### 5. `ReferenceGrant` (cross-namespace guard)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: apollo-gateway-frontend
  namespace: apollo-airlines-apps  # target ns of the cross-ns ref
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: apollo-airlines-ui  # source ns of the cross-ns ref
  to:
    - group: ""
      kind: Service
      name: frontend
```

The Gateway API rule: a HTTPRoute in namespace A can reference a
Gateway or Service in namespace B only if namespace B has a
`ReferenceGrant` whose `from` matches A's `group`+`kind`+`namespace`
and whose `to` matches the target `group`+`kind`+`name`. This is
the same model as Pod's `networkPolicy` allow-list — a default-deny
with explicit allows.

For Set 5, only the frontend needs it (the only cross-ns route).
If you added another service in a different namespace later, you'd
add a second `ReferenceGrant` to the apps ns.

---

## Apply

```bash
cd stages/stage2/set5-envoy-gateway
./scripts/apply.sh
```

The script (8 steps):
1. Rebuilds the frontend image with Set 5's VITE\_\* URLs (same
   shape as Set 4 — no port, real IP from MetalLB)
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts
4. Applies: apps + infra (10 components, all ClusterIP)
5. Applies: 3 init jobs
6. Applies: MetalLB install → wait for controller → IPAddressPool
7. Applies: Envoy Gateway install (--server-side for 2.9MB) →
   GatewayClass → EnvoyProxy → Gateway → ReferenceGrant → 6 HTTPRoutes
   → wait for `Programmed=True`
8. Prints the MetalLB-assigned IP and the `/etc/hosts` lines to add

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **29/29 checks pass**.

| # | Group | What |
|---|---|---|
| 1-4 | Namespaces | apollo-airlines-apps, apollo-airlines-ui, envoy-gateway-system, metallb-system |
| 5-14 | Deployments | 10 apps all Ready |
| 15 | MetalLB controller | `deploy controller` in metallb-system 1/1 |
| 16 | Envoy Gateway control plane | `deploy envoy-gateway` in envoy-gateway-system 1/1 |
| 17 | Envoy proxy data plane | pod(s) with `gateway.envoyproxy.io/owning-gateway-name=apollo-gateway` Ready |
| 18-20 | Init jobs | 3 jobs succeeded |
| 21 | IPAddressPool | apollo-pool in metallb-system |
| 22 | LoadBalancer IP | envoy service has `status.loadBalancer.ingress[0].ip` non-empty |
| 23 | GatewayClass | `eg` exists with `controllerName: gateway.envoyproxy.io/gatewayclass-controller` |
| 24 | Gateway Programmed | `status.conditions[type=Programmed].status == True` |
| 25 | HTTPRoutes | ≥6 HTTPRoutes, all with `status.parents[].controllerName` populated |
| 26-29 | Smoke tests | curl /healthz on identity, /api/flights on flight, / on frontend, full login through Envoy |

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes:
- The 2 app namespaces
- Envoy Gateway (`envoy-gateway-system` namespace + ~20 Gateway API
  CRDs)
- MetalLB (`metallb-system` namespace + 5 CRDs)

The teardown order matters (same as Set 4's teardown): app
namespaces first → Gateway resources → Envoy (with `timeout 60` +
`--force --grace-period=0` fallback for the webhook) → MetalLB.
The Gateway and Envoy webhooks can hang the deletion if the
namespace is deleted out from under them.

---

## Concepts you should be able to answer

1. **What's a `GatewayClass` vs an `IngressClass`?** — Same role, different spec. Both are "this controller handles this kind of resource", but `GatewayClass` is for the Gateway API and `IngressClass` is for Ingress. A cluster can have both — they don't conflict. The `controllerName` field is the discriminator.
2. **Why does the `EnvoyProxy` exist if v1.5.0 defaults to LoadBalancer?** — Belt-and-suspenders, plus future-proofing. If you want to override the Service to a custom `nodePort`, inject a specific Envoy filter, or tune the deployment shape, the `EnvoyProxy` is the right hook. Today it's a no-op; tomorrow it's the place to make the change.
3. **What does `ReferenceGrant` actually do?** — It's the cross-namespace authorization for Gateway API. A HTTPRoute in ns A can reference a Gateway in ns B only if ns B has a `ReferenceGrant` matching A's group+kind+namespace. Same model as `NetworkPolicy` — default-deny with explicit allow-lists. Without it, the frontend HTTPRoute in `apollo-airlines-ui` cannot attach to the Gateway in `apollo-airlines-apps`.
4. **When did Gateway API go GA?** — k8s 1.24 (May 2022). Set 5 uses the `v1` API group `gateway.networking.k8s.io/v1`. Older `v1alpha1`/`v1beta1` is deprecated.
5. **How do the 6 HTTPRoutes + 1 ReferenceGrant work end-to-end?** — The 5 backend HTTPRoutes (identity, flight, booking, search, notification) live in `apollo-airlines-apps` and reference the Gateway in the same namespace. The 6th HTTPRoute (frontend) lives in `apollo-airlines-ui` and references the Gateway cross-namespace; the `ReferenceGrant` in the apps ns explicitly allows this. The 6 routes share the Gateway listener (port 80) and are dispatched by the `hostnames` field.

---

## Why this is the access stack that carries forward

Stages 3-6 (StatefulSets, probes, Helm chart, observability) all
build on **Set 5's access stack**, not Set 4's. Specifically:

- Stage 3: copies Set 5's `gateway/` dir as the k8s/gateway/ baseline
- Stage 5 (Helm chart): bakes the gateway manifests into
  `templates/gateway/`
- Stage 7+: same — every chart render uses the Set 5 access stack

The rationale: Gateway API is the upstream k8s standard, Envoy is the
highest-quality data plane, and MetalLB gives a real LoadBalancer IP
that survives across cluster rebuilds. The Set 5 combination is what
production looks like.

---

## Previous / Next

- **Previous:** [Set 4: Traefik + MetalLB](../set4-metallb-traefik/README.md) — same MetalLB stack, but Traefik is the controller
- **Next:** [Stage 3 — Mission Data](../README.md) — same Set 5 access stack + StatefulSets + PVCs + entrypoint-hook schema + seed Jobs
