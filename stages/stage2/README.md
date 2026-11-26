---
title: "Stage 2: Guidance — Networking & Edge Access"
description: "Progressive networking ladder from internal ClusterIP and cross-namespace DNS to Envoy Gateway API on MetalLB."
---

# Stage 2: Guidance — Networking & Edge Access

Stage 2 takes the single-namespace baseline from Stage 1 and establishes Kubernetes networking across two production namespaces:
- `apollo-airlines-apps`: Backend microservices (`identity`, `flight`, `booking`, `search`, `notification`), databases, and Redis.
- `apollo-airlines-ui`: Frontend web application (`frontend`).

Rather than duplicating full manifest suites, Stage 2 follows a progressive **5-substage ladder**. Workload Deployments and internal Service definitions remain stable; what evolves is **how traffic is discovered internally and routed from the outside edge**.

---

## The Networking Access Ladder

```
Substage 1                 Substage 2            Substage 3                Substage 4             Substage 5
──────────                 ──────────            ──────────                ──────────             ──────────
ClusterIP & DNS     ──►    NodePort       ──►    Traefik Ingress    ──►    MetalLB LoadBalancer ──► Envoy Gateway API
Internal FQDN              High NodePorts        Host routing              L2 ARP real IP         Gateway API CRDs
Endpoints & Slices         30080–30084           Local TLS termination     Port 80 / 443          Canonical Baseline
```

| Substage | Mechanism | Protocol / Port | Learning Outcome |
|---|---|---|---|
| **01-internal-dns** | `Service type: ClusterIP` | Virtual internal IPs | CoreDNS FQDN resolution, `Endpoints` vs `EndpointSlice`, selector binding |
| **02-nodeport** | `Service type: NodePort` | `localhost:30080–30084` | L4 host-to-container forwarding via `kube-proxy`, port target mapping |
| **03-traefik-ingress-tls** | Traefik v3 IngressController | `*.apollo.local:30080 / 30443` | L7 Host routing, Ingress resources, wildcard TLS termination with Secrets |
| **04-metallb** | MetalLB L2 + `type: LoadBalancer` | `*.apollo.local` on MetalLB IP | ARP-based external IP allocation in local clusters, elimination of high NodePorts |
| **05-envoy-gateway** | Envoy Gateway v1.5.0 + MetalLB | `*.apollo.local` on MetalLB IP | Gateway API standard: GatewayClass, Gateway, HTTPRoute, cross-namespace ReferenceGrant, RequestRedirect |

> [!IMPORTANT]
> **Envoy Gateway + MetalLB (Substage 5)** forms the **canonical access stack** that carries forward into Stage 3 and all subsequent stages. Traefik is a required transitional learning experience; Headless Services are introduced in Stage 3 alongside StatefulSets, and NetworkPolicies are deferred to Stage 8 where Calico enforcement makes them observable.

---

## Directory Structure

```
stages/stage2/
├── code/                        # Shared source code for Apollo Airlines services
├── k8s/
│   ├── config/                  # Namespaces (apps, ui), ConfigMaps, Secrets, ServiceAccounts
│   ├── infra/                   # identity-db, flight-db, booking-db, redis (Deployments + ClusterIP)
│   ├── jobs/                    # Idempotent database schema initialization Jobs
│   ├── apps/                    # identity, flight, booking, search, notification, frontend
│   └── substages/
│       ├── 01-internal-dns/     # Substage 1: curl client & cross-namespace DNS inspection
│       ├── 02-nodeport/         # Substage 2: NodePort service definitions (30080–30084)
│       ├── 03-traefik-ingress-tls/ # Substage 3: Traefik DaemonSet, TLS secret generator, Ingresses
│       ├── 04-metallb/          # Substage 4: MetalLB native manifest, IP pool, LoadBalancer Service
│       └── 05-envoy-gateway/    # Substage 5: Envoy Gateway v1.5.0, Gateway, HTTPRoutes, ReferenceGrant
└── scripts/
    ├── build-images.sh          # Builds all 6 application images and loads into kind
    ├── apply.sh                 # Progressive deployment orchestrator (--substage 1-5)
    ├── verify.sh                # Automated checks, depending on the active substage
    ├── verify-tls.sh            # Trusted HTTPS (--cacert) and hostname-rejection checks
    ├── fault-drill.sh           # Randomized blind troubleshooting drill (--inject/--verify/--restore)
    └── teardown.sh              # Clean resource teardown and residue verification
```

---

## Hands-On Lab Walkthrough

### 1. Build and Prepare Cluster
Ensure your local `kind-apollo11` cluster is active, then build the service images (use `--scheme http` for Substages 1–4, or `--scheme https` for Substage 5; `apply.sh` automatically selects the right scheme when run without `--skip-build` — see [CI & Local Image Contract](../../docs/ci-images.md)):

```bash
./stages/stage2/scripts/build-images.sh --cluster apollo11
```

> [!NOTE]
> **Browser UI boundary & local DNS:** The frontend image bakes `http(s)://<service>.apollo.local` API URLs at build time (with no port).
> - **Substages 1–3:** Verify endpoints with `curl` from `curl-client`, NodePorts (`30080–30084`), or Traefik (`30080`/`30443`) — browser login/search calls cannot reach standard ports 80/443 until MetalLB is installed.
> - **Substage 4 (MetalLB):** Browser UI works over HTTP after adding the MetalLB `EXTERNAL-IP` (e.g. `172.18.0.50`) to `/etc/hosts`:
>   ```text
>   172.18.0.50  frontend.apollo.local identity.apollo.local flight.apollo.local booking.apollo.local search.apollo.local
>   ```
> - **Substage 5 (Envoy Gateway):** Rebuild the frontend with `--scheme https` (or run `apply.sh --substage 5` without `--skip-build`) before opening `https://frontend.apollo.local`, so browser API calls use HTTPS and avoid mixed-content blocks (see [Local HTTPS & Gateway Routing](../../docs/local-https.md)).
> - **Docker Desktop (macOS / Windows + WSL2):** MetalLB Layer-2 IPs on the `kind` bridge network are directly routable on Linux Docker Engine, but Docker Desktop isolates the Linux VM network from the host; use the [macOS / WSL2 networking fallback](../../README.md#macos-and-windows-wsl2--docker-desktop-networking-fallback) (`kubectl port-forward` or `cloud-provider-kind`) there.

### 2. Walk Through the Substages

Each substage adheres strictly to the **Learner Contract**: **Build → Inspect → Break → Recover → Explain**.

#### Substage 1: Internal Discovery & Cross-Namespace DNS
Deploy the baseline workloads and inspect CoreDNS discovery:
```bash
./stages/stage2/scripts/apply.sh --substage 1 --skip-build
```
- **Inspect:** Run `kubectl get endpoints -n apollo-airlines-apps` and query services from `curl-client` via `<svc>.<ns>.svc.cluster.local`.
- **Break:** Break the selector on `identity` service (`app: identity-broken`). Observe endpoints drop to `<none>`.
- **Recover:** Restore selector `app: identity`. Endpoints reappear and traffic flows.
- **Details:** See [`stages/stage2/k8s/substages/01-internal-dns/README.md`](k8s/substages/01-internal-dns/README.md).

#### Substage 2: NodePort External Access
Expose services to the host machine via high NodePorts:
```bash
./stages/stage2/scripts/apply.sh --substage 2 --skip-build
```
- **Inspect:** Query `http://localhost:30083/healthz` (Identity) and `http://localhost:30080/` (Frontend).
- **Break:** Change `targetPort` on `identity` service to `9999`. Observe connection failure.
- **Recover:** Restore `targetPort: 8080`.
- **Details:** See [`stages/stage2/k8s/substages/02-nodeport/README.md`](k8s/substages/02-nodeport/README.md).

#### Substage 3: Traefik Ingress & Local TLS
Consolidate traffic behind an L7 reverse proxy with TLS termination:
```bash
./stages/stage2/scripts/apply.sh --substage 3 --skip-build
```
- **Inspect:** Query `https://identity.apollo.local:30443/healthz` and verify TLS certificate subject (`CN=*.apollo.local`).
- **Break:** Delete `apollo-tls-secret` in **both** `apollo-airlines-apps` and `apollo-airlines-ui` (Traefik pools certificates across namespaces, so deleting only one copy leaves `*.apollo.local` active). Observe Traefik fallback to `TRAEFIK DEFAULT CERT`.
- **Recover:** Re-run `generate-certs.sh`. Certificate subject restored.
- **Details:** See [`stages/stage2/k8s/substages/03-traefik-ingress-tls/README.md`](k8s/substages/03-traefik-ingress-tls/README.md).

#### Substage 4: MetalLB & LoadBalancer Services
Eliminate high NodePorts by provisioning real IP addresses on the local Docker network:
```bash
./stages/stage2/scripts/apply.sh --substage 4 --skip-build
```
- **Inspect:** Verify Traefik's `EXTERNAL-IP` (e.g. `172.18.0.50`). Query standard ports 80 and 443 directly on the IP.
- **Break:** Delete `apollo-pool` from `metallb-system`. Recreate Traefik service and observe `<pending>` EXTERNAL-IP.
- **Recover:** Reapply `01-ip-pool.yaml`. External IP is allocated immediately.
- **Details:** See [`stages/stage2/k8s/substages/04-metallb/README.md`](k8s/substages/04-metallb/README.md).

#### Substage 5: Migration to Envoy Gateway API (Canonical Baseline)
Decommission Traefik and transition to the modern Gateway API standard:
```bash
./stages/stage2/scripts/apply.sh --substage 5 --skip-build
```
- **Inspect:** Examine CRDs (`kubectl get crd | grep gateway`). Check Gateway status (`Accepted=True`, `Programmed=True`). Verify `HTTPRoute` attachments, cross-namespace `ReferenceGrant` (`cross-ns.apollo.local` -> `apollo-airlines-ui/frontend`), HTTP-to-HTTPS `RequestRedirect` (`curl -i -H "Host: redirect.apollo.local" "http://${EG_IP}/"` -> `301` `Location: https://redirect.apollo.local/`), and access via the Envoy Proxy LoadBalancer IP.
- **Break (Backend Port):** Patch the `frontend` HTTPRoute's backend port to `9999`. Inspect route status `ResolvedRefs=False` and HTTP 500 error, then restore port `3000`.
- **Break (`ReferenceGrant` / `RefNotPermitted`):** Delete `01a-referencegrant.yaml` (`kubectl delete -f stages/stage2/k8s/substages/05-envoy-gateway/01a-referencegrant.yaml`). Observe `HTTPRoute/frontend-cross-ns` in `apollo-airlines-apps` transition to `ResolvedRefs=False` with reason `RefNotPermitted` and `cross-ns.apollo.local` return HTTP 500 (while `frontend.apollo.local` keeps working).
- **Recover:** Re-apply `01a-referencegrant.yaml`. `frontend-cross-ns` returns to `ResolvedRefs=True` and `cross-ns.apollo.local` serves HTTP 200 again.
- **Details:** See [`stages/stage2/k8s/substages/05-envoy-gateway/README.md`](k8s/substages/05-envoy-gateway/README.md).

---

## Blind Troubleshooting Capstone (Fault Drill)

Once Substage 5 is healthy, test your diagnostic workflow without spoilers using the Stage 2 fault drill:
```bash
./stages/stage2/scripts/fault-drill.sh --inject
```
1. Read only the observed symptom and follow the **Ignition 5-Rung Evidence Ladder** (`Status -> Events -> Detail -> Logs -> Behavior` from [`stages/ignition/README.md`](../ignition/README.md)).
2. Record your investigation in [`learner-work/EVIDENCE_TEMPLATE.md`](../../learner-work/EVIDENCE_TEMPLATE.md).
3. Fix the cluster manually, prove behavioral recovery with `curl`, and validate with:
   ```bash
   ./stages/stage2/scripts/fault-drill.sh --verify
   ```
   (Use `--restore` to reset cleanly if needed, or `--list` to inspect the scenario catalog.)

---

## Automated Verification

Run the verification test suite at any point:
```bash
./stages/stage2/scripts/verify.sh
```
Or via the top-level test harness:
```bash
./test/stage2_test.sh
```

The script dynamically detects the active networking layer (Internal DNS, NodePort, Traefik, Traefik+MetalLB, or Envoy Gateway) and validates:
1. Core namespaces and token automount security on all 13 ServiceAccounts.
2. Readiness of all 10 workloads and completion of database bootstrap Jobs.
3. Active endpoint slices and CoreDNS resolution.
4. Layer-specific routing and TLS certificates.
5. End-to-end user authentication and database queries.

---

## Teardown

To cleanly remove all Stage 2 resources while retaining the underlying kind cluster:
```bash
./stages/stage2/scripts/teardown.sh
```

---

## Stage 2 Notes: HTTPS & Container Images

- **TLS Secret (`apollo-tls-secret`):** Stage 2 uses `apollo-tls-secret` in `apollo-airlines-apps` (and `apollo-airlines-ui` for Substage 3 Traefik), created by `stages/stage2/k8s/substages/03-traefik-ingress-tls/generate-certs.sh` (`--rotate` to renew). Substage 5's Envoy Gateway HTTPS listener terminates TLS using `apollo-tls-secret`, verified by `stages/stage2/scripts/verify-tls.sh` with `curl --cacert`. See [Local HTTPS, TLS Certificates & Gateway Routing](../../docs/local-https.md) for the full `generate-certs.sh` / `mkcert` / break-recover reference.
- **Frontend scheme rebuild:** Substages 1–4 build `frontend` with `--scheme http`; Substage 5 builds with `--scheme https` (`apply.sh` passes `--scheme` automatically unless `--skip-build` is set). See [CI Pipeline, Published GHCR Images & Local Image Contract](../../docs/ci-images.md).

---

## Explain

You should now be able to answer:

1. **ClusterIP & CoreDNS:** Why does `curl http://identity:8080` work inside `apollo-airlines-apps` but fail from `apollo-airlines-ui`, and how does an `EndpointSlice` connect a `Service` selector to Pod IPs?
2. **NodePort:** How does `kube-proxy` forward traffic arriving on a node port (`30080–30084`) to a Service's backing Pods, and why do high NodePorts create friction for browser apps?
3. **Ingress vs. LoadBalancer:** What layer does an Ingress operate at compared to a `Service type: LoadBalancer`, and why does Traefik fall back to `TRAEFIK DEFAULT CERT` only when `apollo-tls-secret` is removed from *both* namespaces?
4. **MetalLB:** Why does a `LoadBalancer` Service stay `<pending>` in a bare `kind` cluster without MetalLB, and how does MetalLB Layer 2 mode advertise `172.18.0.50` on the Docker bridge?
5. **Gateway API:** How do `GatewayClass`, `Gateway`, and `HTTPRoute` separate cluster-operator, infrastructure, and application-developer responsibilities compared to monolithic `Ingress` objects?
6. **`ReferenceGrant` (`RefNotPermitted`):** Why does `Gateway.spec.listeners[].allowedRoutes` not authorize cross-namespace `backendRefs`, and what status condition appears on `HTTPRoute/frontend-cross-ns` when `apollo-gateway-grant` is deleted?
7. **`RequestRedirect`:** How does `HTTPRoute/https-redirect` return an HTTP `301` `Location: https://...` response at the Envoy edge without routing to a backend Pod?

---

## Next Stage: Stage 3 (Mission Data)

In **Stage 3**, we replace ephemeral database Deployments with **StatefulSets**, mount persistent **1Gi PVCs**, introduce **Headless Services** for stable Pod network identities, and bootstrap schemas using PostgreSQL entrypoint hooks (`/docker-entrypoint-initdb.d/`). The **Envoy Gateway + MetalLB** access layer configured in Substage 5 carries over seamlessly as the ingress baseline.
