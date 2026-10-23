# Apollo11 Learning Roadmap

This document is the target curriculum architecture for Apollo11. It separates
the learning sequence from the current implementation state so that stages can
be rebuilt without overstating what is already trusted.

Apollo11 optimizes equally for three outcomes:

1. a coherent path for a learner who starts with basic Linux knowledge;
2. broad, hands-on exposure to the cloud-native ecosystem; and
3. portfolio evidence that the learner can explain and defend.

The required path runs from Launchpad through Stage 9. Stages 10 and 11 are
optional catalogs whose missions declare their own prerequisites.

## Curriculum rules

### Learner contract

Every required substage follows the same loop:

1. **Build:** add the smallest useful mechanism to a known-good baseline.
2. **Inspect:** identify the status, event, log, metric, trace, policy decision,
   or external response that proves it is active.
3. **Break:** run an exact, safe, reversible failure experiment.
4. **Recover:** restore behavior and prove recovery through observable evidence.
5. **Explain:** answer a short set of questions about cause and effect.

A named tool is not taught merely because it is installed. If it does not
participate in this loop, it must be labeled reference-only.

### Structure and delivery

- Each large phase may contain multi-day, independently resumable substages.
- Each phase retains one independently runnable snapshot. Substages use ordered
  manifests, patches, or scripts rather than duplicating the entire snapshot.
- Raw Kubernetes resources remain the primary learning surface through Stage 4.
- Helm becomes the canonical deployment path after Stage 5. Kustomize remains a
  required comparison lab, not a second platform definition maintained forever.
- Troubleshooting begins in Ignition and grows throughout the course using the
  evidence ladder: status, events, `describe`, logs, endpoints, metrics, traces,
  and policy decisions.
- Security defaults appear when a mechanism is introduced. Stage 8 later makes
  those controls explicit, observable, and attackable.
- Each phase produces retained Build/Inspect/Break/Recover evidence. Stage 9
  combines the evidence into a cloud capstone.

## Target sequence

### Launchpad — Container and application baseline

Build Apollo Airlines locally before introducing Kubernetes.

- Container images, Dockerfiles, image layers, Compose, and YAML
- The ten-component application and flagship booking workflow
- Health, readiness, metrics, structured logs, and request propagation
- Secure image defaults where they do not hide the container fundamentals
- Failure and recovery using container, dependency, and persistence evidence

### Ignition — Cluster model and first workload

Establish the Kubernetes mental model and the recurring debugging workflow.

- kind cluster architecture and control-plane responsibilities
- Pods, imperative versus declarative workflows, and reconciliation
- `kubectl` discovery, status, events, `describe`, logs, and endpoint checks
- A first safe Pod failure, replacement, and behavioral recovery proof

### Stage 1 — Liftoff: workloads and configuration

Move the known application onto core Kubernetes workload primitives.

1. Deployments, ReplicaSets, labels, selectors, and Services
2. ConfigMaps, Kubernetes Secrets, namespaces, and workload ServiceAccounts
3. One-shot Jobs for database initialization
4. Rolling updates, rollout status, failed rollout diagnosis, and rollback

### Stage 2 — Guidance: networking and edge access

Move from internal service discovery to the long-lived Gateway API baseline.

1. ClusterIP Services, cross-namespace DNS, and endpoint inspection
2. NodePort as the first direct external-access mechanism
3. Traefik Ingress, host routing, and controlled local TLS
4. MetalLB and the LoadBalancer service model
5. Migration from Ingress to Envoy Gateway API
6. Consumer-level CRD and controller literacy when custom resources first appear

Traefik is a required transitional implementation. Envoy Gateway becomes the
baseline for later stages. Headless Services wait until Stage 3, and
NetworkPolicies wait until Stage 8 where enforcement is observable.

### Stage 3 — Mission Data: state and recovery boundaries

Replace ephemeral state with stable workload identity and persistent storage.

1. StatefulSets, headless Services, and stable Pod identity
2. StorageClasses, PersistentVolumes, PVCs, access modes, and reclaim behavior
3. PostgreSQL entrypoint schema initialization and idempotent seed Jobs
4. Redis persistence
5. Pod-loss, node/storage constraints, backup concepts, and honest data-loss
   boundaries

### Stage 4 — Flight Control: workload reliability and placement

Join lifecycle, resource governance, scheduling, and voluntary disruption into
one causal sequence.

1. Startup, liveness, and readiness probes
2. Graceful termination, lifecycle hooks, and in-flight request draining
3. CPU/memory requests and limits, QoS, throttling, and OOM evidence
4. Scheduler decisions based on requests
5. PriorityClasses, taints/tolerations, affinity, and topology spread
6. PodDisruptionBudgets and drain behavior

Concepts taught here are exercised under harder cloud failures in Stage 9; they
are not advertised there as new topics.

### Stage 5 — Payload Integration: packaging and delivery

Package a known platform, produce artifacts, and reconcile environments.

1. Helm templating, values, rendering, releases, rollback, and chart testing
2. Required Kustomize comparison using dev, staging, and production overlays
3. GitHub Actions validation, image builds, scanning hooks, and GHCR publication
4. Argo CD reconciliation, drift, self-heal, and rollback
5. Promotion across isolated local dev/staging namespaces

Later stages extend Helm. They do not maintain Helm and Kustomize as equivalent
sources of truth.

### Stage 6 — Mission Operations: observability and objectives

Add one signal at a time, using the flagship workflow to expose each signal's
strengths and blind spots.

1. Prometheus metrics and Prometheus Operator resources
2. Grafana exploration and dashboards
3. Alert rules, one booking-workflow SLI/SLO, and an error-budget exercise
4. Centralized logs with Alloy and Loki
5. OpenTelemetry instrumentation and Tempo traces
6. Correlation across metrics, logs, and traces

### Stage 7 — Orbital Maneuvering: performance and elasticity

Measure before optimizing and distinguish application performance from platform
scaling.

1. Establish a repeatable k6 load-test baseline
2. Add observable Redis cache-aside behavior and measure its effect
3. Configure HPA and inspect metric-driven decisions
4. Use VPA in recommendation mode and evaluate its guidance
5. Compare caching, Pod scaling, and resource-right-sizing tradeoffs

Scheduling material moves to Stage 4, where its prerequisites are introduced.

### Stage 8 — Command Module: security enforcement

Stage 8 is a clean rebuild from the verified Stage 7 Helm baseline. Existing
legacy or experimental Stage 8 files are not a trusted implementation source.

1. **Identity and workload baseline:** RBAC, Pod Security Admission, dedicated
   ServiceAccounts, disabled token automount where unnecessary, non-root images,
   seccomp, dropped capabilities, and read-only filesystems
2. **Enforced networking:** replace kindnet with Calico; apply default-deny and
   least-privilege NetworkPolicies; prove allowed and denied flows
3. **External secrets:** Vault plus External Secrets Operator; demonstrate
   bootstrap, reconciliation, rotation, failure, and recovery. **Stakater
   Reloader** turns a rotated Secret into a workload rollout, because Pods that
   read it through `env`/`secretKeyRef` keep the old value until they restart
4. **Admission and supply chain:** Kyverno audit/enforce modes, Trivy CI gates,
   Cosign signing, and rejection of unsigned images

#### Configuration-change rollout policy (Stage 8 substage 3)

Kubernetes delivers changed ConfigMap/Secret data but never restarts a Pod for
it. Stage 8 teaches one rule for who triggers the rollout:

| Change originates in | Trigger | Why |
|---|---|---|
| Git (Helm values, chart ConfigMaps) | `checksum/<name>` Pod-template annotation | The commit is the event; Helm/Argo CD roll the Pods with no extra controller |
| Outside Git (ESO sync from Vault, cert-manager, operators) | Reloader | No commit exists, so something must watch the Secret |

Implementation requirements:

- Pin **Reloader v1.4.22** (latest GA, 2026-09-09) as an offline bundle. v2
  (Operator SDK rebuild) is `v2.0.0-beta.1` / chart `3.0.0-beta.4`; move to it
  only after a GA release passes the same lifecycle. The workload annotations
  are unchanged between v1 and v2, so the move replaces only the bundle.
- **Opt-in only.** Run with `--auto-reload-all=false`; annotate each workload
  explicitly. Prefer named `secret.reloader.stakater.com/reload: "<secret>"`
  over `reloader.stakater.com/auto` so the trigger is visible in the manifest.
- **Do not opt in the Postgres StatefulSets.** `POSTGRES_PASSWORD` is applied
  only at `initdb`; restarting a database with a rotated value changes nothing
  in the database and breaks clients. Database credential rotation needs a
  database-side step and is a separate exercise.
- **Bound the blast radius.** `apollo-airlines-secrets` is read by all five
  backends, so one rotation rolls five Deployments. Use the Stage 4 PDBs and
  `deployment.reloader.stakater.com/pause-period` to avoid a restart storm, and
  show the rollout count in the lab.
- **Demonstrate with `JWT_SECRET`.** Rotating it in Vault → ESO sync → Reloader
  rollout gives observable evidence: tokens minted before the rotation are
  rejected after it, and a fresh login succeeds. Identity signs and Booking,
  Flight and Identity verify with this key, so the lab must also show the
  mixed-key window while old and new Pods overlap, and explain why production
  rotation uses overlapping keys.
- **Lab evidence:** Build (annotation + Reloader), Inspect (Secret
  `resourceVersion`, Reloader logs, new ReplicaSet), Break (rotate with the
  annotation removed and show the stale env value inside the old Pod),
  Recover (restore the annotation and watch the rollout), Explain
  (checksum vs Reloader).

### Stage 9 — Lunar Orbit: AWS cloud lifecycle and capstone

Build and operate one real, production-shaped cloud deployment. AWS/EKS is the
primary provider. GitHub, GHCR, and AWS accounts are required, with local
rehearsals, cost gates, and explicit cleanup controls.

1. Incremental Terraform modules for network, EKS, nodes, registry, storage,
   identity, and platform add-ons
2. Billable-resource inventory and cost expectations before `apply`
3. ECR delivery and deployment of the latest hardened Helm snapshot
4. AWS workload identity, persistent storage, and external access
5. DNS, cert-manager, and automated TLS
6. Pod scaling plus Cluster Autoscaler behavior
7. Node drain, replacement, topology, and PDB exercises
8. A controlled Kubernetes upgrade with pre/post behavioral verification
9. Required Velero backup and restore; advanced disaster recovery remains optional
10. Ownership-scoped teardown and residue/cost audit
11. Required EKS-to-GKE architecture and manifest portability analysis; hands-on
    GKE deployment is optional

The outcome is a **production-shaped learning platform**, not a claim of
production readiness. The capstone ends with an explicit gap analysis covering
database HA, regional resilience, recovery objectives, capacity, security, and
operating ownership.

### Stage 10 — Production Operations Missions

Optional, independent missions with explicit prerequisites:

- Linkerd service mesh
- Argo Rollouts progressive delivery
- ephemeral-container debugging
- Kubeshark traffic inspection
- Chaos Mesh resilience experiments
- advanced backup and disaster recovery
- CloudNativePG replication, failover, and logical backup/restore
- Falco runtime detection with a harmless event and rule tuning

Lifecycle hooks and the baseline DevSecOps pipeline no longer live here; they
move to Stages 4 and 8 respectively.

### Stage 11 — Platform Engineering Specializations

Optional, independent specialization tracks with explicit prerequisites:

- CRD and operator authoring
- KEDA event-driven autoscaling
- k3s homelab and edge deployment
- Backstage developer portal
- Kubecost cost allocation and optimization
- Cluster API declarative cluster lifecycle

## Migration matrix

| Current area | Target area | Migration action | Trust gate |
|---|---|---|---|
| Launchpad | Launchpad | Preserve boundary; strengthen learner evidence and secure defaults | Compose lifecycle plus flagship workflow |
| Ignition | Ignition | Add the reusable troubleshooting evidence ladder and recovery proof | Fresh cluster lifecycle |
| Stage 1 | Stage 1 | Add rolling update/failed rollout/rollback lab; make ServiceAccounts behaviorally meaningful | Clean apply, break/recover, teardown |
| Stage 2 sets 1–5 | Stage 2 substages | Preserve access ladder; make Traefik transitional and Envoy canonical; add local TLS | Each transition proves routing before proceeding |
| Stage 2 Traefik dashboard | Stage 10 or reference | Remove from the required networking chain | Optional mission only |
| Stage 2 headless Services | Stage 3 | Introduce only when StatefulSets consume them | Stable identity inspection |
| Stage 2 reference NetworkPolicies | Stage 8 | Remove inert policy claims; rebuild with Calico enforcement | Observable allow/deny flows |
| Stage 3 | Stage 3 | Correct storage semantics and stale Stage 2 transition claims | Data survival and documented loss boundary |
| Stage 4 lifecycle material | Stage 4 substages 1–2 | Preserve probes and graceful shutdown; add lifecycle hooks | In-flight request recovery proof |
| Stage 4 resources/PDB | Stage 4 substages 3 and 6 | Preserve and connect to scheduling/drain evidence | Scheduler/QoS/disruption proof |
| Stage 7 scheduling lab | Stage 4 substages 4–5 | Move priority, taint, affinity, and topology-spread teaching earlier | Reversible placement lab |
| Stage 5 Helm | Stage 5 canonical path | Preserve and deepen releases, tests, and rollback | Render plus live release behavior |
| Stage 5 Kustomize | Stage 5 comparison | Keep required comparison; stop propagating it as a parallel later-stage platform | Dev/staging/prod comparison |
| Stage 5 CI and Argo CD | Stage 5 delivery substages | Separate artifact production from reconciliation and drift recovery | Real GitHub/GHCR plus local environment promotion |
| Stage 6 observability stack | Stage 6 ordered substages | Split metrics, dashboards, alerts/SLO, logs, traces, and correlation | Signal-specific break/recover exercises |
| Stage 7 Redis cache | Stage 7 substage 2 | Keep required; measure before and after | k6 plus HIT/MISS evidence |
| Stage 7 HPA/VPA | Stage 7 substages 3–4 | Preserve after load baseline and observability | Scaling decisions and recommendation analysis |
| Current Stage 8 tree | Rebuilt Stage 8 | Retire before replacement design; do not inherit implementation trust | New Stage 7-derived lifecycle verification |
| Stage EKS prototype | Stage 9 research input | Rebuild from latest hardened Helm baseline; do not promote prototype scripts | Real-account apply/operate/upgrade/restore/destroy |
| Legacy Stage 9 code/Terraform | Rebuilt Stage 9 | Remove incompatible library-era and simultaneous-cloud scaffolding | AWS-first lifecycle and residue audit |
| Stage 9 topology/PDB topics | Stage 9 exercises | Exercise Stage 4 mechanisms; remove duplicate “new topic” claims | Node failure behavior |
| Stage 9 k6 | Stage 7 | Move initial load-testing instruction earlier; reuse in cloud | Comparable local/cloud results |
| Stage 10 lifecycle hooks | Stage 4 | Move into lifecycle teaching | Graceful termination exercise |
| Stage 10 DevSecOps pipeline | Stage 8 | Consolidate scanning, signing, policy, and enforcement | CI failure plus admission rejection |
| Stage 10 Velero basics | Stage 9 | Make one backup/restore exercise required | Restored application behavior |
| Remaining Stage 10 tools | Stage 10 mission catalog | Make independent and prerequisite-driven | Per-mission learner contract |
| Stage 11 tools | Stage 11 specialization catalog | Keep independent; remove implied linear completion | Per-track learner contract |

## Implementation and trust policy

1. Update the target roadmap and migration matrix before restructuring stages.
2. Rebuild one phase at a time from the latest verified predecessor.
3. Do not retire a trusted phase until its replacement passes a clean lifecycle.
4. Stage 8 is the approved exception: its current implementation has no trust
   inheritance and is retired before replacement design.
5. Preserve the last runnable learner path throughout migration.
6. Do not mark a stage complete from static manifests or historic pass counts.
7. For external systems, verify the real hosted or cloud lifecycle, including
   failure and cleanup—not only rendering or local mocks.

## Known corrections required during migration

- Remove stale Stage 2 guidance claiming Stage 3 uses an init container for
  PostgreSQL schema setup.
- Reconcile Stage 3 explanations of node-local volumes, PVC binding, Pod
  replacement, and actual data-loss boundaries.
- Replace contradictory Stage 8 status claims with the clean-rebuild boundary.
- Rebase cloud work on the latest hardened Helm snapshot rather than Stage 3.
- Replace unresolved or internally inconsistent EKS Terraform resources.
- Rebuild external routing and frontend URL generation around a valid DNS/TLS
  design.
- Replace any region-wide EBS cleanup behavior with ownership-scoped discovery
  and explicit confirmation.
