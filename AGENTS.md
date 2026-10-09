# Apollo11 — Agent Context

## What This Project Is

Apollo11 is a **13-phase Kubernetes/cloud-native learning bootstrap** using **Apollo Airlines** — a flight management system — as the teaching application. Each stage is hands-on: you build real services, deploy them to a real cluster, and add operational concerns (networking, storage, monitoring, security, scaling) stage by stage.

**Target learner:** someone with basic Linux knowledge, no prior k8s or cloud-native experience required.

**Curriculum authority:** [`ROADMAP.md`](ROADMAP.md) defines the approved target
sequence and old-to-new migration. The stage READMEs and the map below describe
the current implementation until each replacement passes a clean lifecycle.

---

## Learner-First Lab Contract

Apollo11 is for a practical learner. New stages and documentation must preserve
learner agency as the platform grows:

1. **Build:** introduce the minimum new Kubernetes mechanism on top of a known
   working baseline.
2. **Inspect:** show the learner which resource, status, event, log, metric, or
   trace proves the mechanism is active.
3. **Break:** provide an exact, safe, reversible failure experiment.
4. **Recover:** restore the system and prove recovery through observable
   behavior, not resource existence alone.
5. **Explain:** end with a short set of questions the learner should now be
   able to answer.

Automation scripts remain the reproducible installation and maintainer
verification path. They must not be the learner's only interaction with a new
concept. Large pass counts establish implementation confidence; each README
must also identify a small number of human-observable learning outcomes.

Do not advertise a concept as taught when the lab only contains an inert
manifest. If a local limitation prevents enforcement (for example kindnet and
NetworkPolicy), label it as reference-only and defer the behavioral claim to a
stage where the effect can be demonstrated.

---

## Verification status after the October gap fixes

The working tree changes context isolation, certificate ownership, frontend API
URLs, token automount, booking SLO rules, and the cache benchmark. Earlier live
pass counts below remain historical evidence only. These changes must pass a
fresh apply → inspect → break → recover → teardown lifecycle before completion
claims are updated. See `verification-runs/GAP_CLOSURE.md` for current evidence.

## Current Implementation Map

| Phase | Name | Focus |
|---|---|---|
| Launchpad | Docker Compose | 10 components, stub code, local dev |
| Ignition | kind cluster | First pod, kubectl basics, cluster architecture |
| Stage 1 | Liftoff | All 10 components as Deployments, ConfigMaps, Secrets, Jobs (single-namespace baseline) |
| Stage 2 | Guidance/N&C | Progressive 5-substage access ladder: ClusterIP & CoreDNS discovery, NodePort, Traefik Ingress + Local TLS, MetalLB LoadBalancer, and Envoy Gateway API baseline. Headless deferred to Stage 3; NetworkPolicies deferred to Stage 8. |
| Stage 3 | Mission Data | StatefulSets + 1Gi PVCs for all 4 stateful workloads (3 PG + redis), schema bootstrap via Postgres `/docker-entrypoint-initdb.d/` ConfigMap mount, idempotent seed Jobs. **Envoy Gateway + MetalLB access stack from Stage 2 set 5 carries over and persists for later completed stages.** |
| Stage 4 | Flight Control | Probes, Guaranteed QoS, lifecycle hooks (preStop), PriorityClass, topology spread, PodDisruptionBudget (148/148 verify) |
| Stage 5 | Payload Integration | Helm chart (full access stack), Kustomize overlays (dev/staging/prod), GitHub Actions CI, **ArgoCD GitOps module** (AppProject + 3 Applications) |
| Stage 6 | Mission Ops | Prometheus, Grafana, OpenTelemetry |
| Stage 7 | Orbital Maneuvering | HPA, VPA, Redis cache, PriorityClass, reversible taint/toleration + affinity + topology-spread lab |
| Stage 8 | Command Module — **clean rebuild planned** | Stage 7 baseline → RBAC/PSA/hardening → Calico NetworkPolicy → Vault/ESO → Kyverno + Trivy/Cosign |
| Stage EKS | Cloud Target — EKS — **prototype** | Structurally reviewed AWS prototype; not yet trusted by a real-account apply/verify/destroy lifecycle |
| Stage 9 | Lunar Orbit — **planned** | Terraform + AWS/EKS lifecycle, DNS/TLS, node scaling/failure, upgrades, Velero restore, cost and teardown; required GKE portability analysis |
| Stage 10 | Mission Extensions — **planned optional missions** | Linkerd, Argo Rollouts, debugging, Kubeshark, Chaos Mesh, and advanced DR as independent labs |
| Stage 11 | Towards Mars — **planned specializations** | CRDs/operators, KEDA, k3s, Backstage, Kubecost, Cluster API as independent labs |

---

## Approved Target Remap

The phase count remains 13. The required linear path is Launchpad through Stage
9; Stages 10 and 11 are optional mission catalogs. The main moves are:

- rolling updates and rollback move into Stage 1;
- Stage 2 becomes an internal-networking and edge-access progression, with
  Traefik transitional, Envoy canonical, local TLS added, and inert future
  resources deferred;
- scheduling moves from Stage 7 into Stage 4 beside resources and disruption;
- Stage 5 is ordered as Helm → Kustomize comparison → CI/GHCR → Argo CD;
- Stage 6 is ordered as metrics → dashboards → alerts/SLO → logs → traces →
  correlation;
- Stage 7 becomes k6 baseline → measurable cache → HPA → VPA;
- Stage 8 is rebuilt cleanly using the selected security toolchain;
- Stage 9 is the real AWS/EKS capstone, including restore and teardown proof;
- lifecycle hooks and the DevSecOps pipeline move out of Stage 10 to Stages 4
  and 8, while one required Velero exercise moves into Stage 9.

Do not update implementation-status claims merely because a target is recorded
in the roadmap.

---

## Apollo Airlines — Services

### App Services (6)

| Service | Tech | Port | Database | Purpose |
|---|---|---|---|---|
| identity | Python/FastAPI | 8080 | identity-db (PostgreSQL 15) | JWT auth, user profiles, passenger management |
| flight | Go/Gin | 8081 | flight-db (PostgreSQL 15) | Flight inventory, seat management |
| booking | Go/Gin | 8082 | booking-db (PostgreSQL 15) | Reservations (flagship service) |
| search | Go/Gin | 8083 | — | Optimised flight search (Redis from Stage 7) |
| notification | Go/Gin | 8084 | — | Event fan-out (Redis from Launchpad) |
| frontend | React/Tailwind | 3000 | — | SPA, served via NGINX in Docker |

### Infrastructure (4)

| Service | Type | Version |
|---|---|---|
| identity-db | PostgreSQL | 15 |
| flight-db | PostgreSQL | 15 |
| booking-db | PostgreSQL | 15 |
| redis | Redis | 7 |

**Total: 10 components in Launchpad.**

---

## Project Structure

```
Apollo11/
├── SPEC.md                   # Full API contracts, DB schemas, endpoints (Apollo Airlines)
├── README.md                 # Top-level stage map
├── ROADMAP.md                # Approved target curriculum + migration matrix
├── AGENTS.md                 # This file
│
├── stages/
│   ├── launchpad/            # Docker Compose — 10 components, stub code
│   │   ├── docker-compose.yml
│   │   ├── README.md
│   │   └── code/             # identity, flight, booking, search, notification, frontend
│   │
│   ├── ignition/             # kind cluster, first Pod, kubectl basics
│   │   └── README.md
│   │
│   ├── stage1/              # All 10 components as Deployments + Jobs
│   │   ├── README.md
│   │   ├── k8s/             # namespace, configmap, secrets, infra/, apps/, jobs/
│   │   ├── scripts/         # build-images.sh
│   │   └── code/            # copy of launchpad code
│   │
│   ├── stage2/              # Namespaces, DNS, NetworkPolicies, Ingress, Gateway API, MetalLB
│   │   ├── README.md         # Top-level stage 2 guide
│   │   ├── NOTES.md          # Research notes: Envoy Gateway version-sweep results, caveats
│   │   ├── code/             # shared source (no code changes in stage 2)
│   │   ├── k8s/              # config, infra, jobs, apps, and substages (01-05)
│   │   └── scripts/          # apply.sh (--substage 1-5), teardown.sh, verify.sh (46–57 checks), build-images.sh
│   ├── stage3/              # StatefulSets, PVCs, PG entrypoint hook, Headless SVCs
│   │   ├── README.md
│   │   ├── code/            # snapshot of stages/stage2/code/  (no code changes)
│   │   ├── k8s/             # config, serviceaccounts, networkpolicies, apps/, jobs/, gateway/, metallb/
│   │   └── scripts/         # apply.sh, teardown.sh, verify.sh, build-images.sh
│   ├── stage4/              # Probes, resource limits, Guaranteed QoS, PDB, graceful SIGTERM
│   │   ├── README.md
│   │   ├── code/            # snapshot of stages/stage3/code/  (probes + SIGTERM added)
│   │   ├── k8s/             # apps/ (probes+resources), pdb/ (NEW), gateway/, metallb/, jobs/, config/
│   │   └── scripts/         # apply.sh, teardown.sh, verify.sh (148 checks), build-images.sh
│   ├── stage5/              # Helm chart + Kustomize overlays + GitHub Actions + ArgoCD GitOps module
│   ├── stage6/              # OTEL SDK + real /metrics + Prometheus + Grafana + Tempo + Loki + Alloy
│   ├── stage7/              # HPA/VPA, Redis cache, practical scheduling lab
│   ├── stage8/              # PLANNED CLEAN REBUILD; current tree is not trusted input
│   ├── stage9/              # PLANNED; current code/k8s/terraform are untrusted legacy scaffolding
│   ├── stage10/             # PLANNED optional missions; current files are untrusted legacy scaffolding
│   ├── stage11/             # PLANNED specializations; current files are untrusted legacy scaffolding
│   └── eks/                 # Stage 2 set 5 + Stage 3 workloads on AWS EKS (NLB + EBS CSI)
│       ├── README.md
│       ├── terraform/       # vpc/, cluster/, storage/, gateway/, network/, ecr.tf
│       └── scripts/         # up.sh, down.sh, apply-workloads.sh, verify.sh, ebs-sweep.sh
│
└── test/                     # Automated verification scripts per stage
```

**Key design principle:** Each large phase has one independently runnable
snapshot. Ordered substages use manifests, patches, or scripts rather than full
snapshot copies. During migration, the currently runnable snapshot remains
available until its replacement passes a clean lifecycle; Stage 8 is the
approved exception and receives no trust inheritance.

---

## Apollo11 vs Apollo11-Docs (Two-Repo Pattern)

**Apollo11** (`/home/darshan/projects/Apollo11/`) — the **code repository**
- All service code, Dockerfiles, Kubernetes manifests, scripts, and stage READMEs live here.
- This is the repo users clone to follow along and run the labs.
- Never modify Apollo11 code based on what's in the docs — the code is the source of truth.

**Apollo11-Docs** (`/home/darshan/projects/apollo11-docs/`) — the **Docusaurus learning site**
- Built with Docusaurus, deployed separately (e.g., Vercel).
- Contains narrative guides, screenshots, step-by-step instructions, architecture diagrams, and explanations.
- Docs reference Apollo11 code by path — the docs don't contain the code itself.
- When updating docs, write detailed instructional content (screenshots, commands, troubleshooting, expected outputs) — don't just summarize. The docs teach; Apollo11 is the lab environment.

**Relationship:** Apollo11 is the lab, apollo11-docs is the textbook. They are separate repos. Apollo11 code changes don't require docs updates (except when behavior changes), but every new topic covered in docs should have corresponding working code in Apollo11.

---

## Stage Details

### Launchpad

**Location:** `stages/launchpad/`

**Components:** 10 total (6 app services + 4 infra)

**Code requirements per service:**
- `/healthz` — liveness probe (returns 200 if process alive)
- `/readyz` — readiness probe (returns 200 only when DB connections + downstream reachability are healthy, 503 otherwise)
- `/metrics` — Prometheus-compatible (`http_requests_total`, `http_request_duration_ms`, `db_connections_active` for stateful services)
- Structured JSON logging: `{"timestamp","level","service","trace_id","span_id","message",...}`
- `X-Request-ID` header propagation (generate if not present, forward on all downstream calls)
- **CORS middleware** on all services (Go and Python) — `Access-Control-Allow-Origin: *`, all methods/headers, 204 for OPTIONS
- **DB connection: always append `?sslmode=disable`** — Go `lib/pq` driver defaults to SSL; PostgreSQL containers in dev have no SSL
- **Graceful `initDB()` with timeout** — use `context.WithTimeout` + `PingContext`; never use infinite retry loops; log errors during retry
- Stub implementations — return hardcoded but valid-appearing JSON

**Seed data (present from first `docker compose up`):**
- 6 airports: BOM, DEL, SIN, DXB, LHR, JFK
- 6 flights: AA101, AA102, AA201, AA202, AA301, AA401 (today + 30 days)
- 2 users: admin@apolloairlines.com/admin123 (ADMIN), passenger@apolloairlines.com/pass123 (PASSENGER)

**Infrastructure init:** PostgreSQL init scripts via `/docker-entrypoint-initdb.d/` pattern.

**Current Launchpad hardening and evidence:**

- all 6 application images declare non-root runtime users;
- Compose gives application containers read-only root filesystems, `/tmp`
  tmpfs mounts, `no-new-privileges`, and drops all capabilities;
- `.env.example` defines the local credential contract and `.env` is ignored;
- Dozzle is behind the optional `tools` profile because Docker socket access is
  privileged even with a read-only bind mount;
- Booking forwards the passenger JWT to Identity and uses a short-lived
  `SERVICE` JWT for Flight seat mutations;
- Flight, Search, and Booking expose dependency-aware readiness, and all six
  applications expose minimal Prometheus text metrics; and
- `scripts/verify.sh` passes 73 checks covering profiles, container hardening,
  endpoints, a reversible booking, and request-ID evidence. The manual database
  outage and persistence labs remain required learner interactions.

---

### Ignition

**Location:** `stages/ignition/`

**Status:** Complete. A fresh three-node kind lifecycle passed 14/14 checks on
2026-09-05; the isolated verification cluster and its context were removed.

Ignition uses one declarative BusyBox HTTP Pod to establish the recurring
troubleshooting ladder: status, events, `describe`, logs, and endpoint behavior.
The learner first creates the same workload imperatively, then moves to the
committed manifest. Two reversible failures expose different reconciliation
boundaries: killing the supervised HTTP process makes the kubelet restart the
container while preserving the Pod UID; deleting the bare Pod leaves it absent
until the learner reapplies the manifest, producing a new UID. Both recoveries
end with an HTTP response rather than an object-existence check.

`scripts/verify.sh` validates the manifest and cluster, exercises both failure
paths, and passes 14 checks. It is context-guarded and leaves a healthy Pod for
inspection; the README owns explicit workload and cluster cleanup plus residue
audit commands.

---

### Stage 1 (Liftoff)

**Location:** `stages/stage1/`

**Status:** Complete. The clean apply → inspect → break → recover → teardown
lifecycle passed 167/167 checks on 2026-09-05 with zero namespace residue.

**Kubernetes tree (35 files, 42 rendered resources):**
- `namespace.yaml` — `apollo-airlines` namespace
- `configmap.yaml` — service ports, internal URLs, database names
- `secrets.yaml` — POSTGRES_PASSWORD, JWT_SECRET
- `serviceaccounts.yaml` — 13 dedicated identities with token automount disabled
- 4 infra Deployments + Services (identity-db, flight-db, booking-db, redis)
- 3 strict, bounded Init Jobs + Init ConfigMaps; SQL failures remain observable
- 6 app Deployments + Services (identity, flight, booking, search, notification, frontend)
- `kustomization.yaml` — top-level resource list
- `scripts/apply.sh` — builds, loads, applies in dependency order, and waits
- `scripts/verify.sh` — 167 resource, identity, endpoint, workflow, replacement,
  rollout-failure, and rollback checks
- `scripts/teardown.sh` — deletes the owned namespace and proves absence
- `scripts/build-images.sh` — builds + loads images into kind

Stage 1 carries Launchpad's verified auth propagation, dependency readiness,
Prometheus-text endpoints, non-root image defaults, and frontend build contract.
The Kubernetes-specific change remains the deployment layer. Flight seed data
uses `(flight_number, departure_time)` uniqueness and creates 186 rows across
31 days; `psql` runs with `ON_ERROR_STOP` rather than masking errors.

---

### Stage 2 (Guidance/N&C)

**Location:** `stages/stage2/`

**Architecture:** Same 10 workloads deployed across two namespaces (`apollo-airlines-apps` and `apollo-airlines-ui`), organized into a **5-substage progressive access ladder**. Workload Deployments and ClusterIP Services remain uniform; each substage introduces one new edge-routing mechanism following the learner contract (**Build → Inspect → Break → Recover → Explain**).

| Substage | Mechanism | Protocol / Port | Verify Result |
|---|---|---|---|
| `01-internal-dns` | `Service type: ClusterIP` | Virtual internal IPs | 46/46 pass |
| `02-nodeport` | `Service type: NodePort` | `localhost:30080–30084` | 48/48 pass |
| `03-traefik-ingress-tls` | Traefik v3 Ingress + Local TLS | `*.apollo.local:30080 / 30443` | 49/49 pass |
| `04-metallb` | MetalLB L2 + `type: LoadBalancer` | `*.apollo.local` on MetalLB IP | 46/46 pass |
| `05-envoy-gateway` | Envoy Gateway v1.5.0 + MetalLB | `*.apollo.local` on MetalLB IP | 57/57 pass |

**Namespaces (2):**
- `apollo-airlines-apps` — identity, flight, booking, search, notification, identity-db, flight-db, booking-db, redis, init jobs
- `apollo-airlines-ui` — frontend

**Progressive layout:**
```
stages/stage2/
├── code/                        # shared source; includes booking/auth reliability backports
├── k8s/
│   ├── config/                  # 2 namespaces, configmap, secrets, 13 serviceaccounts
│   ├── infra/                   # identity-db, flight-db, booking-db, redis (ClusterIP baseline)
│   ├── jobs/                    # 3 idempotent init DB jobs
│   ├── apps/                    # 6 app services (identity, flight, booking, search, notification, frontend)
│   └── substages/
│       ├── 01-internal-dns/     # Substage 1: curl client & cross-namespace DNS inspection
│       ├── 02-nodeport/         # Substage 2: NodePort service definitions (30080–30084)
│       ├── 03-traefik-ingress-tls/ # Substage 3: Traefik DaemonSet, TLS cert generator, Ingresses
│       ├── 04-metallb/          # Substage 4: MetalLB native manifest, IP pool, LB Service
│       └── 05-envoy-gateway/    # Substage 5: Envoy Gateway v1.5.0, Gateway, HTTPRoutes, ReferenceGrant
└── scripts/
    ├── apply.sh                 # progressive orchestrator (--substage 1-5, default 5)
    ├── teardown.sh              # deletes namespaces + controllers, verifies 0 residue
    ├── verify.sh                # 46–57 dynamic checks per active stack
    └── build-images.sh          # builds all 6 images and loads into kind
```

**Hostnames (substages 3–5):** `frontend.apollo.local`, `identity.apollo.local`,
`flight.apollo.local`, `booking.apollo.local`, `search.apollo.local`.

**Headless Services:** Deferred to Stage 3 when StatefulSets consume them.

**ServiceAccounts:** 13 SAs (identity, flight, booking, search, notification,
frontend, identity-db, flight-db, booking-db, redis + 3 init job SAs with `automountServiceAccountToken: false`). No
`Role`/`RoleBinding` yet — those arrive in Stage 8.

**NetworkPolicies:** Manifests provided for reference
(default-deny + per-service allowlist). **NOT applied by `apply.sh`** because
kind's default `kindnet` CNI does not enforce NetworkPolicies. The
educational value is in reading them, not in enforcement.

**Traefik v3.1 IngressController (sets 2, 3, 4):** DaemonSet on control-plane,
listens on NodePort 30443. Host header routing across 5 Ingresses. Set 3
adds the Traefik dashboard via an `IngressRoute` (Traefik CRD) pointing at
the controller's built-in `api@internal` service. Requires the controller
to be started with `--configFile=/etc/traefik/traefik.toml` (static config
that explicitly enables the API + dashboard).

**Envoy Gateway v1.5.0 (set 5):**
- `install.yaml` (~2.9MB) bundled in-repo (offline-friendly) — must use
  `kubectl apply --server-side` (exceeds 256KB last-applied-config limit otherwise)
- `install.yaml` does **NOT** create a `GatewayClass` — create it manually:
  `controllerName: gateway.envoyproxy.io/gatewayclass-controller`
- Auto-created Envoy Service is `type: LoadBalancer` by default — MetalLB
  assigns a real IP, no port-forward needed
- The `EnvoyProxy` resource (`spec.provider.kubernetes.envoyService.type:
  LoadBalancer`) is what wires the Gateway to the auto-created Service
- Cross-namespace HTTPRoute attachments need `parentRef.namespace` and
  `allowedRoutes` permission. Cross-namespace backend references need a
  `ReferenceGrant` in the backend namespace
- 6 HTTPRoutes + 1 ReferenceGrant (frontend in `ui` ns → Gateway in `apps` ns)

**MetalLB v0.14.5 native (sets 4, 5):**
- L2 mode (ARP/NDP) — no router config required
- `metallb-native.yaml` (~1900 lines) bundled in-repo — use
  `kubectl apply --server-side --force-conflicts` (webhook manages its own CA)
- IP pool: `172.18.0.50–100` on default kind docker network (must not
  overlap with kind node IPs)
- Wait for webhook controller pod to be `1/1` before creating IPAddressPool

**Envoy Gateway version-sweep (set 5):** All 5 versions tested
(v1.2.4, v1.3.0, v1.4.0, v1.4.5, v1.5.0) correctly materialize the
data-plane listener via LDS and serve HTTP 200. **Chose v1.5.0** for set
5 — see `stages/stage2/NOTES.md` for the test methodology. Newer versions
(v1.6, v1.7, v1.8) also pass; v1.5 minimizes risk of new surprises while
matching the version we already validated.

**Service type rules across sets:**
- Set 1: `type: NodePort + nodePort: 30xxx`
- Sets 2/3: `type: ClusterIP` (NodePort removed)
- Set 4: `type: LoadBalancer` (MetalLB gives it a real IP)
- Set 5: `type: LoadBalancer` (EnvoyProxy + MetalLB)

**Frontend image:** VITE\_\* API URLs are baked at build time. Each set
rebuilds the frontend image with its own URL pattern. The shared
`stages/stage2/code/frontend/vite.config.js` uses `process.env.VITE_*`
(or a sane localhost default) so build args take effect. `apply.sh` handles
both build and kind load.

**Stage 2 code changes vs stage1:** No networking-feature changes. A later correctness backport makes booking forward the user's JWT to Identity, use a short-lived `SERVICE` JWT for internal Flight seat mutations, and bound Notification's Redis startup wait. The same reliability contract is carried through Stages 3–6.

**Lessons learned in this restage:**
- The 4-set → 5-set restage happened because the Envoy Gateway set
  (originally `set3-gateway-nodeport`) was using a broken Envoy
  Gateway v1.2.4 that needed a `kubectl patch` loop to override the
  auto-created `ClusterIP` Service. Splitting "introduce LoadBalancer
  IP via MetalLB" (set 4) from "introduce Gateway API" (set 5) gives
  each set a single new concept.
- The 4 manifest sets that were deleted (`set3-gateway-nodeport/`,
  `set4-metallb-gateway/`) are not in git history anymore; if you
  need to revisit the original design, see the v1.2.4 install.yaml
  in the commit history.

---

### Stage 3 (Mission Data)

**Location:** `stages/stage3/`

**Architecture:** Same 10 workloads + same Envoy Gateway + MetalLB access stack as Stage 2 **set 5** (the restaged layout). The 4 stateful workloads (`identity-db`, `flight-db`, `booking-db`, `redis`) move from `Deployment` + `emptyDir` to `StatefulSet` + `1Gi PVC`. App Deployments, frontend, gateway, MetalLB, ServiceAccounts, NetworkPolicies are **unchanged**. The Stage 2 set-5 access stack is the **persisted baseline for all later stages** (4–11).

| Group | Files | What |
|---|---|---|
| `k8s/config/` | 4 | Namespaces, ConfigMap, Secret, 13 ServiceAccounts (automount disabled) |
| `k8s/apps/identity-db/` | 4 | `*-sts.yaml` (StatefulSet + 1Gi VCT + init SQL mounted at `/docker-entrypoint-initdb.d`), `*-svc.yaml` (ClusterIP), `*-svc-headless.yaml`, `*-init-script.yaml` (ConfigMap) |
| `k8s/apps/flight-db/` | 4 | same shape (UNIQUE on `(flight_number, departure_time)` so the same flight can fly daily) |
| `k8s/apps/booking-db/` | 4 | same shape |
| `k8s/apps/redis/` | 3 | `redis-sts.yaml` (with AOF enabled), `redis-svc.yaml`, `redis-svc-headless.yaml` |
| `k8s/apps/{identity,flight,booking,search,notification,frontend}/` | 12 | Unchanged Deployment + Service |
| `k8s/jobs/` | 6 | 3 × `seed-*.yaml` Jobs + 3 × `*-db-seed` ConfigMaps (idempotent `ON CONFLICT DO NOTHING`) |
| `k8s/gateway/` | 11 | Envoy Gateway v1.5.0 install + GatewayClass + EnvoyProxy + Gateway + 6 HTTPRoutes + ReferenceGrant |
| `k8s/metallb/` | 2 | MetalLB v0.14.5 native install + IPAddressPool + L2Advertisement |
| `scripts/` | 4 | `apply.sh` (preflight + 7 numbered steps, waits for StatefulSets and Gateway programming), `teardown.sh` (deletes namespaces + Gateway + controllers with 0 residue), `verify.sh` (68 checks including reversible failure experiment), `build-images.sh` |

**Storage:** `storageClassName` is **intentionally omitted** from `volumeClaimTemplates` — uses kind's default `local-path` StorageClass. PVCs are `ReadWriteOnce, 1Gi`. PVs are node-local on the kind worker. Reclaim policy is `Delete` (default), so deleting the PVC reclaims the local-path volume.

**Schema bootstrap (entrypoint hook, not init container):** The schema (CREATE TABLE) is mounted as a ConfigMap at `/docker-entrypoint-initdb.d/init.sql` inside the Postgres container, with `PGDATA=/var/lib/postgresql/data/pgdata`. The official Postgres image's entrypoint runs the SQL during `initdb` on first start (empty PVC). On every subsequent restart, the data dir is non-empty and the entrypoint skips both `initdb` and `/docker-entrypoint-initdb.d/`. **Why not a custom init container:** that approach deadlocks — the init's `pg_isready` against `127.0.0.1` waits for the main container, but the kubelet gates the main container on init's success. The entrypoint hook is the standard Postgres pattern and doesn't have this issue.

**Seed jobs:** 3 one-shot Jobs (`seed-identity-db`, `seed-flight-db`, `seed-booking-db`) that insert seed data using `ON CONFLICT DO NOTHING`. The `seed-booking-db` Job is intentionally near-empty (booking has no seed data) but kept to prove the schema-applied and to keep the pattern uniform.

**Stable pod identity:** The StatefulSet `serviceName` is wired to the existing headless services (`identity-db-headless`, `flight-db-headless`, `booking-db-headless`, `redis-headless`). Pods get FQDNs like `identity-db-0.apollo-airlines-apps.svc.cluster.local` for direct pod-to-pod addressing (used by the StatefulSet controller, not by app code).

**Why entrypoint hook vs Job for schema:** The entrypoint runs the SQL once on first start of the pod (when the data dir is empty). A Job runs once per cluster creation — if the StatefulSet pod moves to a fresh node with an empty PVC, the entrypoint re-applies the schema (idempotently). Seed stays as a Job because re-inserting 186 flight rows on every restart is wasteful (even with `ON CONFLICT DO NOTHING`).

**Code changes vs stage2:** None. `stages/stage3/code/` is a snapshot of `stages/stage2/code/`. App code doesn't know whether the DB is behind a Deployment or StatefulSet.

**Critical (from the b968cb9 review pass — read before changing the frontend):**
- `stages/stage3/code/frontend/vite.config.js` must read `VITE_*` from
  `process.env` (synced from Stage 2's fix). The old `define` block
  with hardcoded `:8080` URLs would have made the frontend ignore
  the Dockerfile's `--build-arg VITE_IDENTITY_URL=...`.
- `stages/stage3/code/frontend/nginx.conf` (new) defines the three
  probe endpoints (`/healthz`, `/readyz`, `/healthz/{startup,live,ready}`)
  that the frontend Deployment's liveness + readiness probes point at.
  The old Dockerfile's inline `RUN echo > default.conf` had no
  probe endpoints, which would have made the frontend pod's
  readiness probe fail continuously and the Service would have
  no endpoints.
- `stages/stage3/code/frontend/Dockerfile` uses `COPY nginx.conf`
  instead of the inline `RUN echo` pattern.

---

### Stage 4 (Flight Control)

**Location:** `stages/stage4/`

**Status:** ✅ Complete. 148/148 verify checks pass on a fresh kind cluster (probes, live execution, Guaranteed QoS, preStop hooks, PriorityClasses, topology spread, PDBs, SIGTERM drain, and Eviction API budget proof).

**Architecture:** Same 10 workloads as Stage 3 + same Envoy Gateway + MetalLB access stack. This stage adds **probes** (so the kubelet can detect unhealthy pods), **resource governance** with Guaranteed QoS (so the scheduler can place pods predictably and OOM events are bounded), **lifecycle preStop hooks and graceful SIGTERM shutdown** (so in-flight requests drain cleanly instead of dropping), **PriorityClasses & topology spread constraints** (so mission-critical booking/search pods have scheduling priority and replicas are balanced across nodes), and **PodDisruptionBudgets** (so voluntary disruptions cannot take down the UI or booking service). The Stage 2 set-5 access stack (Envoy + MetalLB) is unchanged.

| Group | Files | What |
|---|---|---|
| `k8s/config/` | 5 | Namespaces, ConfigMap, Secret, 13 ServiceAccounts (automount=false), PriorityClasses (`apollo-airlines-app-critical`, `apollo-airlines-app-low`) |
| `k8s/apps/{identity,flight,booking,search,notification,frontend}/` | 12 | Add `startupProbe` + `livenessProbe` + `readinessProbe` (all 3 HTTP, distinct paths), `lifecycle.preStop` hook (`sleep 5`), `topologySpreadConstraints` (`maxSkew: 1`), `priorityClassName` (critical for booking/search, low for notification), `resources.requests == resources.limits` (Guaranteed QoS), `terminationGracePeriodSeconds: 30` |
| `k8s/apps/{identity-db,flight-db,booking-db,redis}/` | 7 | Add `resources.requests == resources.limits` + `terminationGracePeriodSeconds: 60`. **No new probes** — liveness + readiness already in stage 3. **No `startupProbe`** — Postgres' `initdb` / Redis init is the implicit start. |
| `k8s/pdb/` | 2 | `booking-pdb.yaml` (apps ns), `frontend-pdb.yaml` (ui ns) — both `minAvailable: 1` |
| `k8s/jobs/` | 6 | Verbatim from stage 3 (idempotent seed Jobs + ConfigMaps) |
| `k8s/gateway/` | 11 | Envoy Gateway v1.5.0 install + GatewayClass + EnvoyProxy + Gateway + 6 HTTPRoutes + ReferenceGrant |
| `k8s/metallb/` | 2 | MetalLB v0.14.5 native install + IPAddressPool + L2Advertisement |
| `scripts/` | 4 | `apply.sh` (8 steps, applies config/apps/pdb/jobs/gateway/metallb), `teardown.sh` (0 residue), `verify.sh` (148 checks including Eviction API PDB proof & placement lab), `build-images.sh` |

**Probe paths (split into 3 distinct endpoints):**

| Path | Returns | k8s probe | Purpose |
|---|---|---|---|
| `/healthz/startup` | 200 once HTTP server is up | `startupProbe` | Gives the container 30s to bootstrap before liveness takes over (initialDelay 0, period 5s, failureThreshold 6) |
| `/healthz/live` | 200 unconditionally | `livenessProbe` | "Process is alive" — restart on failure (initialDelay 15, period 10s, failureThreshold 3) |
| `/healthz/ready` | 200 if DB/Redis reachable, 503 otherwise | `readinessProbe` | "Can handle traffic" — pull from Service endpoints on failure (initialDelay 5, period 5s, failureThreshold 3) |
| `/healthz` | 200 | — | Legacy back-compat (smoke tests, external monitoring) |
| `/readyz` | 200 | — | Legacy back-compat alias of /healthz/ready |

**Why split them:** with a single endpoint, a temporary DB blip
would trigger a liveness restart — a self-inflicted outage.
Conflating "is the process alive?" with "is the process able to
serve right now?" is one of the most common k8s configuration bugs.

**Resource tiers (Guaranteed QoS — `requests == limits`):**

| Tier | Workloads | CPU | Memory |
|---|---|---|---|
| App default | identity, flight, search | 100m | 128Mi |
| Flagship | booking | 200m | 256Mi |
| Low traffic | notification | 50m | 64Mi |
| Edge | frontend (NGINX) | 50m | 64Mi |
| Postgres | identity-db, flight-db, booking-db | 200m | 256Mi |
| Redis | redis | 100m | 128Mi |

`requests == limits` is the **definition** of Guaranteed QoS.
Burstable is a deliberate Stage 7+ concern when we have variable
load (HPA, VPA). Stage 4 is the right time to *teach* Guaranteed
because students can reason about it deterministically.

**`terminationGracePeriodSeconds`:**

| Workload | Grace | Why |
|---|---|---|
| 6 app Deployments | 30s | Matches the `srv.Shutdown(30s)` budget in Go / `timeout_graceful_shutdown=30` in uvicorn |
| 4 StatefulSets (PG, redis) | 60s | Postgres checkpoint + WAL flush, Redis AOF rewrite can spike |

**PodDisruptionBudgets:**

| PDB | ns | minAvailable | Replicas | Effect |
|---|---|---|---|---|
| `booking-pdb` | apollo-airlines-apps | 1 | 2 | A node drain cannot take booking below 1 ready pod |
| `frontend-pdb` | apollo-airlines-ui | 1 | 2 | A node drain cannot take the UI offline |

PDBs only apply to **voluntary** disruptions (the eviction API).
Node hardware failure and OOMKill ignore PDBs and are handled by
replica count + re-creation.

**Graceful shutdown code patterns:**

*Go services (flight, booking, search, notification):*
```go
srv := &http.Server{Addr: ":" + port, Handler: r}
go srv.ListenAndServe()                      // non-blocking
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
logJSON("INFO", svc, "Received SIGTERM, shutting down gracefully", ...)
srv.Shutdown(ctx)                            // drain in-flight, 30s budget
db.Close()                                   // release connection pool
```
`srv.Shutdown(ctx)` is the Go stdlib primitive: it stops accepting
new connections, waits for in-flight requests to complete, and
returns. If `ctx` expires first, `Shutdown` returns
`context.DeadlineExceeded` and the kubelet SIGKILLs us.

*Python/identity:*
```python
def _log_sigterm(signum, frame):
    log_json("INFO", "identity-service", "Received SIGTERM, ...")
signal.signal(signal.SIGTERM, _log_sigterm)
uvicorn.run(app, host="0.0.0.0", port=8080,
             timeout_graceful_shutdown=30, access_log=False)
```
uvicorn's default SIGTERM handler sets `should_exit=True`, triggering
a graceful drain via `Server.shutdown()`. Our handler runs *first*
(just logs), then uvicorn's runs and drains. The `lifespan` context
manager handles DB cleanup.

*Frontend (NGINX):* receives SIGTERM, exits within ~1s. No app-level
drain needed.

**Code changes vs stage3:**

- All 4 Go services (flight, booking, search, notification) + 2-stage
  Python (identity): add 3 new probe handlers + `http.Server.Shutdown`
  graceful drain
- `code/identity/main.py`: add `import signal` + register a prior
  SIGTERM handler that logs; uvicorn's handler does the actual drain.
  Add `timeout_graceful_shutdown=30` to `uvicorn.run()`
- `code/frontend/nginx.conf` (new file): three `location = /healthz/*`
  blocks returning 200 unconditionally
- `code/frontend/Dockerfile`: `COPY nginx.conf` instead of inline
  `echo > default.conf`
- All Dockerfiles for backend services: **no changes** (binary
  entrypoint is the same)
- `stages/stage4/code/` is a snapshot of `stages/stage3/code/` with
  the above edits

**Verify target:** 148 checks (43 carried baseline + 105 Stage 4 checks: probes, QoS, preStop, PriorityClasses, topology spread, PDB Eviction API proof, and placement lab):
- 18: probes configured on 6 app Deployments (3 probes × 6 deps)
- 12: probes on 4 sts (liveness + readiness each, NO startupProbe)
- 10: resources.requests/limits on all 10 workloads
- 10: QoS class is Guaranteed on all 10 pods
- 10: terminationGracePeriodSeconds (30 for apps, 60 for sts)
- 4: PDBs exist + status populated
- 18: live probe responses — `kubectl exec ... wget /healthz/{startup,live,ready}` × 6 apps
- 1: frontend bundle contains all four `*.apollo.local` API URLs and no localhost API URLs
- 4: behavioural demo (delete booking pod → "Received SIGTERM" in
  logs + replacement Ready; delete frontend pod → replacement
  serves /healthz/ready)

**Lessons from this stage (read before changing):**

1. **`kubectl logs <old-pod> --previous` returns NotFound once the
   pod is removed from the API server.** The graceful-shutdown
   verify uses `kubectl logs --follow` in a background process
   *before* the delete, then greps the captured output. See
   `stages/stage4/scripts/verify.sh` line ~417.

2. **uvicorn's default SIGTERM handler is the right one — don't
   replace it.** `sys.exit(0)` on SIGTERM drops in-flight requests.
   Register a *prior* handler that just logs and let uvicorn do
   the drain.

3. **DB StatefulSets don't need a `startupProbe`.** Postgres' own
   `initdb` blocks the main process from accepting connections,
   so `pg_isready` is an implicit startup check. A `startupProbe`
   would race with the entrypoint.

4. **NGINX reports Ready before it serves HTTP in some cases.**
   The frontend verify retries 30× and re-fetches the pod name
   each iteration (the API server returns the old deleting pod
   for 1-2s after `kubectl delete --wait=false`).

5. **The teardown script from Stage 3 handles the
   Gateway/MetalLB ordering correctly. Reused verbatim.** The
   teardown order is: app namespaces → Gateway + HTTPRoutes →
   Envoy (with `timeout 60` + `--force --grace-period=0`
   fallback) → MetalLB.

6. **The frontend's probe paths return 200 unconditionally.**
   NGINX has no local DB/Redis to check. Readiness on the
   frontend is "process is alive and serving", which a successful
   HTTP response already proves.

---

### Stage 5 (Payload Integration)

**Location:** `stages/stage5/`

**Status:** ✅ Implementation complete and locally verified (2026-08-22). Helm/dev passed **153/153**, Kustomize/dev passed **142/142**, and Argo CD passed **74/74** using a temporary read-only Git fixture. Every path completed a clean purge with zero namespace/PVC/related-CRD residue. The hosted GitHub Actions run and first GHCR release publication remain external checks triggered by the next push/tag.

**k8s manifest changes:** None at the workload level (Stage 5 is a packaging layer). The chart's `templates/` produce the same Deployments/StatefulSets/Services that Stage 4's `k8s/` tree contains.

**New files:**
- `helm/apollo11/Chart.yaml` + `values.yaml` — chart metadata + configurable defaults
- `helm/apollo11/bundles/envoy-gateway-install.yaml` — v1.5.0 (~2.8MB, offline-friendly)
- `helm/apollo11/bundles/metallb-native.yaml` — v0.14.5 (~67KB, offline-friendly)
- `helm/apollo11/templates/` — 19 templates (config, infra, apps, ui, pdb, jobs, gateway)
- `overlays/base/generated.yaml` — complete 61-resource plain-manifest base (no runtime Helm dependency)
- `overlays/{dev,staging,prod}/` — environment overlays (replicas, image tags, PDBs in prod only)
- `scripts/apply.sh` — mode-aware: `--mode helm|kustomize` + `--env dev|staging|prod`
- `scripts/teardown.sh` — symmetric teardown + `--purge` for namespace cleanup
- `scripts/verify.sh` — 153 Helm checks / 142 Kustomize checks, including routes, seed rows, frontend bundle, login, and packaging ownership
- `scripts/build-images.sh` — 6 services + frontend with VITE_* URLs from `values.yaml`
- `.github/workflows/main.yml` — replaces stub. Lint + matrix build + GHCR push (no deploy)
- `argocd/install.sh` — Argo CD v3.5.1 install; the 34,050-line official bundle is vendored for offline use
- `argocd/uninstall.sh` — symmetric teardown of the ArgoCD system
- `argocd/platform/platform.yaml` — shared GatewayClass, MetalLB pool, and six isolated environment namespaces
- `argocd/projects/project.yaml` — `AppProject` restricting tenants to six namespaces, no cluster-scoped resources
- `argocd/applications/{dev,staging,prod}.yaml` — 3 isolated Applications; dev/staging automated, prod manual
- `argocd/scripts/bootstrap.sh` — idempotent registration of project + 3 apps, `--sync` to force-sync
- `argocd/scripts/verify.sh` — 74 GitOps checks including real replica-drift self-heal
- `argocd/scripts/teardown.sh` — apps-only / `--full` / `--purge` levels
- `argocd/DEMO.md` — 101 walkthrough (install, bootstrap, sync, drift demo, rollback, teardown)
- `argocd/ARGOCD.md` — complete ArgoCD reference guide (reconciliation model, architecture, AppProject/Application/ApplicationSet, source types, sync policies, hooks/waves/windows, RBAC, multi-cluster, HA, anti-patterns)

**ArgoCD Application sync policies (per env):**

| Application | Sync | Prune | SelfHeal | Image tag | PDBs |
|---|---|---|---|---|---|
| apollo11-dev     | automated | true  | true  | `:latest`  | off |
| apollo11-staging | automated | true  | true  | `:latest`  | off |
| apollo11-prod    | **manual** | false (in options) | false | `:v1.0.0` pinned | on |

Dev and staging auto-converge on git push; prod is human-gated and pins the image to `v1.0.0`. Its source revision remains `main` until that release tag actually exists; pin `targetRevision` as part of the release transaction.

**Code changes vs stage4:** None (snapshot of `stages/stage4/code/`).

---

### Stage 6 (Mission Ops)

**Location:** `stages/stage6/`

**Status:** ✅ Complete and locally verified (2026-08-25). Helm/dev passed **190/190** and Kustomize/dev passed **180/180** on clean lifecycles, including real metrics, healthy Prometheus targets, the Grafana Envoy route, an end-to-end booking trace in Tempo, and Alloy log delivery to Loki. Both paths completed a full purge with no Stage 6 namespace, PVC, controller, or related-CRD residue. The four-Application Argo CD layout validates statically; live reconciliation awaits a Git revision containing the uncommitted Stage 6 work.

**k8s manifest changes:**
- **Prometheus Operator v0.93.0** — bundled outside the chart so Helm's release Secret stays below Kubernetes' 1 MiB object limit
- **Prometheus v3.13.1** (operator-managed, 5Gi PVC) — 5 ServiceMonitors + Apollo alert rules
- **Grafana** (Deployment, 1Gi PVC) — 5 dashboards as ConfigMaps, 3 datasources (Prometheus, Loki, Tempo)
- **OTEL Collector** (DaemonSet) — OTLP gRPC receiver on :4317, exports to Tempo
- **Tempo** (Deployment, 5Gi PVC) — single-binary trace backend, 48h retention
- **Loki** (Deployment, 5Gi PVC) + **Grafana Alloy** (DaemonSet) — log aggregation and per-node collection
- **5 ServiceMonitors** (one per backend) — Prometheus auto-discovers /metrics endpoints
- **Grafana HTTPRoute** + **ReferenceGrant** — exposed at `grafana.apollo.local` via existing Envoy Gateway
- **New namespace** `apollo-observability` with read-only cluster discovery RBAC
- **Argo CD ownership** — dev/staging/prod Applications deploy tenant workloads with observability disabled; a fourth shared Application owns the observability namespace and resources

**Code changes vs stage5:**
- **All 4 Go services** (booking, flight, search, notification): +OTEL SDK init (otlptracegrpc, otlpmetricgrpc), otelgin middleware, promhttp /metrics handler with real `http_requests_total` + `http_request_duration_ms` counters, logJSON pulls trace_id/span_id from active OTEL span context, outbound HTTP clients inject W3C `traceparent` header
- **Identity (Python)**: +OTEL SDK init, FastAPIInstrumentor, Psycopg2Instrumentor, requests instrumentation, prometheus_client /metrics with real exposition format
- **Booking/Flight service authentication:** booking forwards the caller JWT only to Identity and mints a 5-minute `role=SERVICE` JWT for internal seat decrement/restore calls; Flight accepts `SERVICE` or `ADMIN` on that internal endpoint. The trace test uses the passenger account and verifies both booking and cancellation.
- **Canonical schema contract:** Stage 5/6 packaging uses `booking_reference VARCHAR(20)` without a mandatory `total_price`, and Flight retains `updated_at`, matching `SPEC.md` and the earlier stage schemas.
- **All 5 backend Dockerfiles**: unchanged (new deps picked up via `go mod download` / `pip install -r requirements.txt`)
- **Frontend**: unchanged (browser-side RUM OTEL is a Stage 8+ concern)
- **`/metrics` endpoint**: now returns Prometheus exposition format (`# HELP` / `# TYPE` lines, real counter values) instead of placeholder JSON

---

### Stage 7 (Orbital Maneuvering)

**Location:** `stages/stage7/`

**Status:** ✅ Complete. On 2026-08-26 Helm/dev passed **211/211**, the
practical lab scaled search **1→3→1** across both workers and restored all
temporary state, and Kustomize/dev passed **200/200**. Both refreshed paths
completed clean purges. The earlier Helm/staging **211/211** live-VPA evidence
still applies; current dev/staging/prod and Argo CD renders validate statically.

**k8s and packaging changes:**
- HPA for search: default 2–10 replicas at 70% CPU; dev 1–3; prod 3–20 at 60%
- VPA for search in `Off` recommendation mode; disabled in dev
- metrics-server v0.8.1 bundle with kind TLS compatibility
- 2 PriorityClasses; booking/search are critical, notification is low priority
- Search tolerates `workload=search:NoSchedule`, softly prefers
  `apollo11.io/search-pool=dedicated`, and uses hostname topology spread with
  `maxSkew: 1`. `scripts/scaling-lab.sh` applies the concrete worker metadata,
  proves cross-worker placement during HPA scale-out, and removes it afterward.
- Both Helm and committed Kustomize delivery paths carry the Stage 7 resources

**Code changes vs stage6:**
- Search Service: Redis caching (key: `search:{origin}:{destination}:{date}`, TTL 5min), bounded startup, graceful degradation, and lazy reconnection
- `X-Cache: HIT/MISS` header on search responses
- `cache_hits_total` / `cache_misses_total` metrics and OTEL cache child spans
- Stage 6 booking authentication, trace propagation, real metrics, and bounded notification startup are preserved verbatim

---

### Stage 8 (Command Module)

**Location:** `stages/stage8/`

**Status:** ⚠️ Clean rebuild planned. The current tree does not inherit
implementation trust and must not be copied forward, even where experimental
Apollo Airlines files exist.

**Implementation boundary:** Retire the current tree before replacement design,
then rebuild from the trusted Stage 7 Helm snapshot. The ordered substages are:

1. observable RBAC, Pod Security Admission, workload ServiceAccounts, non-root
   images, seccomp, dropped capabilities, and read-only filesystems;
2. Calico plus enforced NetworkPolicy allow/deny experiments;
3. Vault plus External Secrets Operator bootstrap, rotation, failure, and
   recovery; and
4. Kyverno audit/enforce policy, Trivy CI gates, Cosign signatures, and
   admission rejection of unsigned images.

---

### Stage EKS (Cloud Target — EKS)

**Location:** `stages/eks/`

**Trust warning:** This tree is research input only. It is based on Stage 2 set
5 plus Stage 3 rather than the latest hardened platform, and it has no verified
real-account lifecycle. Known blockers include an unresolved load-balancer
controller Terraform reference, invalid frontend/DNS routing assumptions, a
broken teardown script path, and an EBS sweep whose region-wide scope is unsafe.
Do not run its teardown scripts as a trusted cleanup path.

**New files:**
- `terraform/network/` — `terraform-aws-modules/vpc/aws`, `10.0.0.0/16`, 2 public + 2 private subnets, 1 NAT in AZ-0 (saves $33/mo)
- `terraform/cluster/eks.tf` — `terraform-aws-modules/eks/aws` v21.x, k8s 1.31, encryption-at-rest with KMS, access entries replace aws-auth ConfigMap
- `terraform/cluster/node-groups.tf` — 2 × t3.small spot across 2 AZs, AL2023 AMI
- `terraform/cluster/addons.tf` — 6 EKS managed addons: vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, aws-ebs-csi-driver, aws-load-balancer-controller
- `terraform/cluster/pod-identity.tf` — 4 IAM roles + EKS Pod Identity associations (EBS CSI, LBC, VPC CNI, Pod Identity agent)
- `terraform/cluster/policies/lbc-policy.json` — vendored LBC IAM policy from `kubernetes-sigs/aws-load-balancer-controller`
- `terraform/cluster/kms.tf` — KMS key for EKS secrets encryption
- `terraform/storage/storageclass.tf` — `ebs-gp3` StorageClass (default, `WaitForFirstConsumer`)
- `terraform/gateway/envoy-gateway.tf` — LBC Helm release + 11 `kubectl_manifest` applies for the Stage 2 set 5 Envoy Gateway stack
- `terraform/gateway/envoyproxy.yaml.tftpl` — the **only** Apollo11 k8s manifest that's different from Stage 2 set 5: 5 LBC annotations on the EnvoyProxy so the LBC materialises an NLB instead of relying on MetalLB
- `terraform/gateway/{envoy-gateway-install,gatewayclass,gateway,reference-grant,httproute-*}.yaml` — verbatim copies of the Stage 2 set 5 manifests
- `terraform/ecr.tf` — 6 ECR repos (one per service), MUTABLE tags, scan-on-push, lifecycle policy (keep last 10)
- `scripts/up.sh` — terraform init + apply + kubeconfig + wait-for-NLB-active
- `scripts/apply-workloads.sh` — Stage 3 apply.sh ported for EKS (ECR push instead of kind load; MetalLB and gateway install steps skipped)
- `scripts/down.sh` — ordered teardown (namespaces → Envoy stack → LBC Helm → terraform destroy → ECR purge → EBS sweep → ENI sweep)
- `scripts/verify.sh` — ~40 checks across 5 groups (cluster+addons, StatefulSets+PVCs+EBS PVs, deployments, NLB+Envoy, end-to-end + PVC persistence demo)
- `scripts/ebs-sweep.sh` — delete orphaned EBS volumes left over from interrupted destroys

**Status:** Stage EKS records an early EKS deployment shape for Stage 2 set 5 +
Stage 3. It is neither structurally nor behaviorally trusted and must be rebuilt
for Stage 9 rather than promoted in place.

**Key design choices:**

1. **Single NAT in AZ-0 only.** Saves ~$33/mo vs 2 NATs. AZ-1 nodes pay cross-AZ data transfer on NAT-routed egress (~$0.01/GB; cents for dev). Toggle via `single_nat_gateway = true` (default) / `false`.
2. **EKS Pod Identity, not IRSA.** Newer, simpler, AWS-recommended. The eks_aws module's `service_account_role_arn` field is wired to Pod Identity roles.
3. **NLB scheme toggleable.** `nlb_scheme = "internet-facing"` (default, public DNS) or `"internal"` (saves $7.20/mo public IPv4 fees, needs VPN/bastion).
4. **`nlb-ip-target-type: ip`** so the NLB routes to pod IPs directly (requires VPC CNI in ip mode, the EKS default). Saves the NodePort hop.
5. **`deletion_protection = false`** so `terraform destroy` works in one shot. Flip to `true` for prod.
6. **State backend is local.** ~5-10MB state file. Documented swap path to S3 + DynamoDB for shared dev.
7. **`aws-auth` ConfigMap replaced by access entries.** Modern path on EKS 1.30+. The single admin principal gets `cluster-admin` policy via access entries.
8. **No MetalLB install.** The LBC + NLB replaces it. Stage 2 set 5's MetalLB manifest was deliberately NOT copied.
9. **Frontend images built and pushed to ECR.** `apply-workloads.sh` rewrites `apollo11/*:latest` → `<ECR_REGISTRY>/apollo11-dev/*:latest` on the fly via `sed`, then `kubectl apply -f` with the rewritten manifests.
10. **Frontend VITE_* URLs use `nip.io` by default** so the user doesn't have to edit `/etc/hosts` to hit the cluster. Override with `FRONTEND_HOST_SUFFIX=.apollo.local` if you want the canonical Apollo Airlines URL pattern.

**What this stage does NOT do:**

- No GKE module (Stage 9 covers GKE).
- No production HA (single NAT, no multi-region, no cluster autoscaler, no PodDisruptionBudgets).
- No Stage 4 probes + resource limits — the manifests in `stages/stage4/` are layered on top of Stage 3, not EKS. To add them on EKS, copy the probe paths from Stage 4 manifests into the apply-workloads.sh image-rewrite step.
- No observability stack (Stage 6 covers Prometheus + Grafana + OTEL).
- No service mesh (Stage 10 covers Linkerd).

**The Stage 2 set 5 manifests are reused verbatim; the only changes are 5 LBC annotations on the `EnvoyProxy` + the `ebs-gp3` StorageClass.**

---

### Stage 9 (Lunar Orbit)

**Location:** `stages/stage9/`

**Status:** ⚠️ Planned, not implemented. Current files are unverified legacy
scaffolding. The standalone `stages/eks/` tree is a structural prototype, not
real-account evidence.

**Implementation boundary:** AWS/EKS is the primary lifecycle. Build incremental
Terraform modules, identify billable resources, deploy the latest hardened Helm
snapshot, add DNS/TLS, drive Pod and node scaling, perform node-failure and
upgrade drills, prove a Velero restore, then destroy and audit for billable
residue. Require an EKS-to-GKE portability analysis; hands-on GKE remains
optional. Do not build two clouds simultaneously or claim HA without evidence.

---

### Stage 10 (Mission Extensions)

**Location:** `stages/stage10/`

**Status:** ⚠️ Planned optional missions. Current files are unverified legacy
scaffolding.

Build Linkerd, Argo Rollouts, live debugging/traffic inspection, Chaos Mesh, and
advanced disaster recovery as independent labs. Each must start from a known-good baseline,
introduce one mechanism, run an observable experiment, and restore the
baseline. They are not a mandatory linear prerequisite chain.

---

### Stage 11 (Towards Mars)

**Location:** `stages/stage11/`

**Status:** ⚠️ Planned optional specializations. Current files are unverified
legacy scaffolding.

Treat the flight-status CRD/operator, KEDA, k3s, Backstage, Kubecost, and
Cluster API as independent specializations with their own prerequisites,
resource/cost budget, failure exercise, verification, and cleanup.

---

## Code Evolution Per Stage

| Stage | Code additions |
|---|---|
| launchpad | Base stubs — all services return hardcoded JSON. `/healthz`, `/readyz`, `/metrics` implemented. Structured logging with trace_id/span_id fields. X-Request-ID propagation. CORS middleware on all Go services. `addSSLMode()` helper for PostgreSQL connections (`?sslmode=disable`). `initDB()` uses `context.WithTimeout(15s)` + `PingContext` + error logging (no more infinite retry loops). `sql.NullString` for nullable DB columns. **Frontend upgraded to React/Tailwind CSS** (modern airline UI, VITE env vars for API URLs, multi-stage Docker build). Admin panel pages (Dashboard, Flights CRUD, Bookings view). |
| stage1 | (no code change — k8s deployment layer only) |
| stage2 | (no code change — networking layer only) |
| stage3 | (no code change — storage layer only) |
| stage4 | All 4 Go services (flight, booking, search, notification) and the FastAPI identity service expose 3 distinct probe endpoints: `/healthz/startup` (returns 200 once the HTTP server is up), `/healthz/live` (returns 200 unconditionally), `/healthz/ready` (returns 200 if the dependency is reachable, 503 otherwise). Legacy `/healthz` and `/readyz` kept returning 200 for back-compat. Graceful SIGTERM shutdown: Go services use `signal.Notify(quit, syscall.SIGTERM)` + `srv.Shutdown(ctx)` (30s timeout) + `db.Close()`. Python/identity registers a prior SIGTERM handler that logs and lets uvicorn's built-in drain (`timeout_graceful_shutdown=30`). Frontend NGINX config (`nginx.conf`) adds three `location = /healthz/*` blocks returning 200 unconditionally — readiness on the frontend is a kubelet-level check, not a downstream check. |
| stage5 | (no code change — packaging layer only) |
| stage6 | Full `/metrics` endpoint with all required Prometheus metrics. OTEL SDK integrated (traces + metrics). `trace_id` and `span_id` fields already present in logs since launchpad — now propagated through all calls. |
| stage7 | Search Service: Redis caching (key: `search:{origin}:{destination}:{date}`, TTL 5min). `X-Cache: HIT/MISS` header on search responses. All Go services: graceful shutdown fully implemented. |
| stage8 | **Planned clean rebuild:** retire the current tree, then rebuild from Stage 7; no trusted code additions yet |
| stage9 | **Planned:** AWS/EKS cloud lifecycle from the hardened Helm baseline; no trusted code additions yet |
| stage10 | **Planned optional missions:** no trusted code additions yet |
| stage11 | **Planned optional specializations:** no trusted code additions yet |

---

## Key Constraints / Conventions

- **mise** for environment management (`mise.toml` + `prep.sh`) — no manual `apt install` for k8s tools
- **Dockerfiles** use multi-stage builds and live in each service's directory
- **Go services:** `golang:1.22-alpine` — flight, booking, search, notification
- **Python service:** `python:3.12-slim` — identity
- **Frontend:** `node:20-alpine` for build, `nginx:alpine` for serving
- **PostgreSQL:** `postgres:15-alpine`
- **Redis:** `redis:7-alpine`
- **YAML frontmatter** on all documentation/readme files
- **Do NOT auto-git-commit** — write files locally, commit only when user explicitly asks
- **No npm on host** — frontend builds happen inside Docker (multi-stage: node builds → nginx serves)
- **User prefers:** concise responses, ASCII diagrams for architecture, comparison tables

---

## mise Tools

Currently in `mise.toml`: kubectl, kind, Helm, jq, Kustomize, Argo CD, k6,
Trivy, task, k3d, and minikube. Docker is a prerequisite that `prep.sh`
checks but does not install. `./prep.sh --verify` checks the whole toolchain.

Add future-stage tools only when their lab is implemented and verified; do not
advertise an uninstalled tool as part of the current learner environment.

---

## Stage Completion Status

| Phase | Status | Details |
|---|---|---|
| Launchpad | ✅ Complete | 10 default workloads, non-root/read-only app containers, dependency-aware readiness, Prometheus text endpoints, full 30-day flight schedule (186 rows), reversible flagship workflow, 74/74 verify |
| Ignition | ✅ Complete | Fresh three-node lifecycle; 14/14 checks cover the evidence ladder, container restart, bare-Pod deletion, and behavioral recovery |
| Stage 1 | ✅ Complete | 42 resources; 13 tokenless workload identities; 167/167 checks cover Jobs, flagship workflow, Pod replacement, failed rollout, rollback, and clean teardown |
| Stage 2 | ✅ Complete | 5-substage progressive access ladder: 01-internal-dns 46/46, 02-nodeport 48/48, 03-traefik-ingress-tls 49/49, 04-metallb 46/46, 05-envoy-gateway 57/57. Envoy Gateway v1.5.0 + MetalLB carries forward. |
| Stage 3 | ✅ Complete | 4 StatefulSets + PVCs + entrypoint-hook schema + seed jobs, 53/53 verify (Envoy+MetalLB access stack persists for stages 4–11) |
| Stage 4 | ✅ Complete | Probes (startup/live/ready) on 6 apps, Guaranteed QoS on all 10 pods, PDBs for booking + frontend, graceful SIGTERM on all backends, topology spread, PriorityClasses, Eviction API proof, 148/148 verify |
| Stage 5 | ✅ Complete locally | Helm 153/153, Kustomize 142/142, Argo CD 74/74; all clean lifecycle tests passed. Hosted Actions/GHCR publication awaits the next push/tag. |
| Stage 6 | ✅ Complete locally | Helm 190/190 and Kustomize dev 180/180; full metrics/traces/logs behavior and clean purges verified. Argo CD's 4-Application layout validates statically; live reconciliation awaits the next explicitly authorized Git revision. |
| Stage 7 | ✅ Complete locally | Helm/dev 211/211 + practical scale 1→3→1 across 2 workers; Kustomize/dev 200/200; clean purges and zero lab residue. Earlier Helm/staging 211/211 proved live VPA; current renders validate statically. |
| Stage 8 | ⚠️ Clean rebuild pending | Current worktree is not a trusted input; replacement starts from verified Stage 7 Helm. |
| Stage 9–11 | ⚠️ Pending | Prototype or legacy scaffolding exists, but none is a trusted implementation boundary yet. |

---

## Observability Trace Design (Stage 6+)

The trace for a Create Booking request:

```text
Booking Service (root span)
    │
    ├── Identity Service: GET /api/users/{id}
    │
    ├── Flight Service: GET /api/flights/{id}
    │
    ├── Flight Service: PATCH /api/flights/{id}/seats
    │
    ├── Booking DB: INSERT bookings
    │
    └── Notification Service: POST /api/notify
```

Total spans: 6 spans across 3 services + 1 DB span.

This single trace demonstrates:
- Cross-service context propagation
- Database query timing
- Downstream dependency latency
- Failure points for fault injection (Stage 10)

---

## Booking Service — Flagship Workflow

The Booking Service is the primary vehicle for teaching distributed systems concepts:
- Stage 1-3: Deploy and observe basic health
- Stage 4: Reliable restarts with probes
- Stage 6: OTEL tracing across service boundaries
- Stage 7: Redis caching on search (downstream of booking workflow)
- Stage 7: Load testing with k6 before caching and autoscaling comparisons
- Stage 10: Chaos injection + service mesh fault injection

---

## Kubernetes Namespace Structure

| Namespace | Contents | Stages |
|---|---|---|
| apollo-airlines | All 10 components in a single namespace | Stage 1, Launchpad (compose) |
| apollo-airlines-apps | identity, flight, booking, search, notification + all DBs/redis + init jobs | Stage 2+ |
| apollo-airlines-ui | frontend | Stage 2+ |

Note: Stage 2 collapsed the originally-planned 3-namespace layout
(`infra`/`apps`/`ui`) down to 2 (`apps`/`ui`) — see Stage 2 details above.

---

## Port Map

| Service | Port | Notes |
|---|---|---|
| frontend | 3000 | React SPA |
| identity | 8080 | FastAPI |
| flight | 8081 | Go/Gin |
| booking | 8082 | Go/Gin |
| search | 8083 | Go/Gin |
| notification | 8084 | Go/Gin |
| identity-db | 5432 | PostgreSQL |
| flight-db | 5432 | PostgreSQL (separate PVC) |
| booking-db | 5432 | PostgreSQL (separate PVC) |
| redis | 6379 | Redis 7 |

---

## Seed Data (Always Present)

Airports: BOM, DEL, SIN, DXB, LHR, JFK

Flights: AA101, AA102, AA201, AA202, AA301, AA401 (today + 30 days, deterministic UUIDs)

Users:
- admin@apolloairlines.com / admin123 (ADMIN)
- passenger@apolloairlines.com / pass123 (PASSENGER)
