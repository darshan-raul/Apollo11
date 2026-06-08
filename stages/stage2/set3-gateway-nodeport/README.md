---
title: "Stage 2 / Set 3: Envoy Gateway API (port-forward)"
description: "Gateway API resources with Envoy Gateway as the data plane, accessed via kubectl port-forward."
---

# Stage 2 / Set 3 — Envoy Gateway API

The same 10 components. But instead of Traefik + Ingress, we use
**Envoy Gateway** (the reference implementation of Gateway API). The
Gateway controller auto-creates an Envoy proxy pod; you create a
`GatewayClass`, `Gateway`, and `HTTPRoute` per service. Since the
auto-created Envoy Service is `ClusterIP` in kind, we reach it with
`kubectl port-forward`.

| | |
|---|---|
| **New concept** | GatewayClass, Gateway, HTTPRoute, ReferenceGrant, cross-namespace `parentRef.namespace` |
| **Access pattern** | `kubectl port-forward` to the Envoy Service, then `curl -H 'Host:...' http://localhost:8888/...` |
| **Controller** | Envoy Gateway v1.2.4 (controller + auto-created Envoy proxy) |
| **DNS** | `/etc/hosts` (5 entries → 127.0.0.1) |
| **Result** | **26/26 verify checks pass** |

---

## Why port-forward instead of NodePort?

Envoy Gateway v1.2.4 doesn't expose `spec.infrastructure.serviceOverride`
in its `Gateway` API. The auto-created Envoy Service is hard-coded
`type: ClusterIP`. We have three options:

1. **Patch the Service** to NodePort after creation — works, but fragile
2. **Port-forward** — simple, idiomatic for kind, no patches
3. **Use MetalLB** (Set 4) — real LoadBalancer IP, no port-forward

This set uses option 2. Set 4 uses option 3.

---

## Architecture

```
       Browser
         |
         |  HTTP, Host: <svc>.apollo.local
         v
   +-----------+     +-----------+      +-----------+
   |  :8888    |     | :8888     |      |  Envoy    | (auto-created
   | localhost |     | kubectl   |      |  proxy    |  by Gateway)
   +-----------+     | port-     |      +-----------+
                     | forward   |            |
                     +-----------+            | routes by hostname
                                               v
                            +----------+ +----------+ +----------+
                            | identity | | frontend | | flight   |  (ClusterIP)
                            +----------+ +----------+ +----------+
```

---

## Prerequisites

- A kind cluster
- Container images for the 6 services built and loaded

```bash
kind create cluster --name apollo11 --config stages/ignition/kind-config.yaml
```

---

## Apply

```bash
cd stages/stage2/set3-gateway-nodeport
./scripts/apply.sh
```

The script:
1. Rebuilds the frontend image with Set 3's VITE\_\* URLs
2. Loads all 6 service images into kind
3. Applies: namespaces → config → serviceaccounts → apps + infra → init jobs
4. Applies Envoy Gateway install (`kubectl apply --server-side`)
5. Applies GatewayClass, Gateway, ReferenceGrant, 6 HTTPRoutes
6. Patches the auto-created Envoy Service from `LoadBalancer` to `ClusterIP` (kind has no LB)
7. Waits for the Gateway to become `Programmed`
8. Prints port-forward instructions and `/etc/hosts` lines

After the script finishes, start the port-forward in **another terminal**:

```bash
SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system svc/$SVC 8888:80
```

Then set up local DNS:

```bash
# Add to /etc/hosts:
127.0.0.1  frontend.apollo.local identity.apollo.local flight.apollo.local \
            booking.apollo.local search.apollo.local
```

---

## Verify

```bash
./scripts/verify.sh
```

Expected: **26/26 checks pass**. The verify script will refuse to run the
smoke tests if the port-forward isn't active (it checks port 8888 first).

Manual smoke test (with port-forward running):

```bash
curl -H 'Host: identity.apollo.local' http://localhost:8888/healthz
curl -H 'Host: flight.apollo.local'   http://localhost:8888/api/flights
open http://frontend.apollo.local:8888
```

---

## Teardown

```bash
./scripts/teardown.sh
```

Removes both `apollo-airlines-*` namespaces, the Envoy Gateway controller,
and the auto-created Envoy proxy/Service (via the bundled `install.yaml`).

---

## What's in here (file map)

```
k8s/
├── config/                       # VITE_* with apollo.local:8888 (port-forward port)
├── serviceaccounts/accounts.yaml
├── networkpolicies/               # reference only
├── apps/                          # same as Set 1 (ClusterIP)
├── jobs/                          # 3 init DB jobs
└── gateway/                       # ← NEW vs Set 1
    ├── 00-envoy-gateway-install.yaml  # bundled upstream install.yaml (~1.5MB)
    ├── 00a-gatewayclass.yaml          # GatewayClass `eg` (manually created — not in install.yaml)
    ├── 01-gateway.yaml                # Gateway: listener 80, allowedRoutes: All
    ├── 01a-referencegrant.yaml        # cross-namespace frontend route
    ├── 02-httproute-identity.yaml     # in apollo-airlines-apps
    ├── 03-httproute-flight.yaml
    ├── 04-httproute-booking.yaml
    ├── 05-httproute-search.yaml
    ├── 06-httproute-notification.yaml
    └── 07-httproute-frontend.yaml    # in apollo-airlines-ui, parentRef.namespace explicit
```

---

## Important caveats (read this!)

### GatewayClass `eg` is **not** in the install.yaml

The bundled `00-envoy-gateway-install.yaml` contains:
- All CRDs (Gateway API + Envoy's own)
- Namespace, ServiceAccount, RBAC
- ConfigMap (with the EnvoyGateway spec in `data.envoy-gateway.yaml`)
- The controller Deployment
- Cert-gen Job, webhook Service, etc.

But it does **not** create a `GatewayClass` resource. The `EnvoyGateway`
config in the ConfigMap tells the controller to *expect* a GatewayClass
named `eg` — but you must create the `GatewayClass` resource yourself.
`apply.sh` does this in step 6.

### The cross-namespace frontend HTTPRoute

The `frontend` HTTPRoute lives in `apollo-airlines-ui` but its `parentRef`
points to the `apollo-gateway` in `apollo-airlines-apps`. Gateway API
requires:

1. **Explicit `parentRef.namespace: apollo-airlines-apps`** in the HTTPRoute
   (without it, the parentRef defaults to the HTTPRoute's own namespace
   and won't match)
2. **A `ReferenceGrant`** in the `apollo-airlines-ui` namespace allowing
   the `apollo-airlines-apps` namespace's HTTPRoutes to reference the
   `frontend` Service

`apply.sh` creates both.

### Why the install.yaml needs `--server-side`

The bundled file is ~1.5MB / 39,000 lines. Client-side apply stores the
entire file in the `kubectl.kubernetes.io/last-applied-configuration`
annotation, which has a 256KB limit. Server-side apply avoids this.

### The Envoy proxy's auto-created Service

When you create a `Gateway`, Envoy Gateway's infrastructure manager creates:
- An `EnvoyProxy` Deployment (the data plane)
- A `Service` for the Envoy proxy — hard-coded `type: LoadBalancer`

In kind, LoadBalancer Services never get an IP. `apply.sh` patches the
Service to `ClusterIP` so port-forward works. Set 4 uses MetalLB to
provide a real IP, so the patching is unnecessary there.

---

## Concepts you should be able to answer

1. What's the difference between a `GatewayClass` and a `Gateway`?
2. Why does `HTTPRoute` need a `parentRef`?
3. Why does the frontend `HTTPRoute` need `parentRef.namespace: apollo-airlines-apps`?
4. What is a `ReferenceGrant` and when do you need one?
5. Why did we have to patch the Envoy Service from `LoadBalancer` to `ClusterIP`?
6. What's the role of the `EnvoyProxy` resource that the controller creates implicitly?

---

## Next set

[Set 4: Envoy Gateway + MetalLB](../set4-metallb-gateway/README.md) — same Gateway, but with a real LoadBalancer IP. No more port-forward.
