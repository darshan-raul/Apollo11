---
title: "Stage 2: Guidance — Networking & Edge Access"
description: "Progressive networking ladder from internal ClusterIP and cross-namespace DNS to Envoy Gateway API on MetalLB."
---

> **Current verification status:** the context, TLS, and contract fixes in this
> working tree require a fresh runtime lifecycle. Counts below record earlier
> revisions; use the current verifier's summary rather than expecting those totals.

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
| **05-envoy-gateway** | Envoy Gateway v1.5.0 + MetalLB | `*.apollo.local` on MetalLB IP | Gateway API standard: GatewayClass, Gateway, HTTPRoute, cross-namespace ReferenceGrant |

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
    ├── verify.sh                # Comprehensive 30+ check verification suite
    └── teardown.sh              # Clean resource teardown and residue verification
```

---

## Hands-On Lab Walkthrough

### 1. Build and Prepare Cluster
Ensure your local `kind-apollo11` cluster is active, then build the service images:

```bash
./stages/stage2/scripts/build-images.sh --cluster apollo11
```

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
- **Break:** Delete `apollo-tls-secret` in `apollo-airlines-apps`. Observe Traefik fallback to `TRAEFIK DEFAULT CERT`.
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
- **Inspect:** Examine CRDs (`kubectl get crd | grep gateway`). Check Gateway status (`Accepted=True`, `Programmed=True`). Verify HTTPRoute attachments and access via the Envoy Proxy LoadBalancer IP.
- **Break:** Patch the `frontend` HTTPRoute's backend port to `9999`. Inspect route status `ResolvedRefs=False` and HTTP 500 error.
- **Recover:** Restore port `3000`. Route recovers to `Accepted=True`.
- **Details:** See [`stages/stage2/k8s/substages/05-envoy-gateway/README.md`](k8s/substages/05-envoy-gateway/README.md).

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

## Next Stage: Stage 3 (Mission Data)

In **Stage 3**, we replace ephemeral database Deployments with **StatefulSets**, mount persistent **1Gi PVCs**, introduce **Headless Services** for stable Pod network identities, and bootstrap schemas using PostgreSQL entrypoint hooks (`/docker-entrypoint-initdb.d/`). The **Envoy Gateway + MetalLB** access layer configured in Substage 5 carries over seamlessly as the ingress baseline.

## HTTPS in the canonical Envoy substage

Substage 5 now carries local TLS forward. Its installer generates and preserves
`apollo-tls-secret` in the application namespaces and builds frontend API URLs
as HTTPS. Use `--context kind-apollo11` (or the supported dev context) for both
installation and certificate recovery. The certificate generator accepts
`--rotate` for deliberate renewal. It binds all Secret changes to the selected
context, independently of the current kubeconfig context.

Inspect the HTTPS listener's `ResolvedRefs` condition, extract the public
certificate from the Secret, and use `curl --cacert` with `--resolve` for a DNS
hostname. `curl -k` proves neither hostname validity nor browser trust. Configure
local DNS and trust before opening `https://frontend.apollo.local`, then verify
that login, search, and booking requests use HTTPS in the browser Network panel.
Delete the apps-namespace TLS Secret to break HTTPS; HTTP remains the separate
baseline. Re-run the generator with the same context, extract its replacement
certificate, and prove trusted HTTPS and an application workflow recover.
