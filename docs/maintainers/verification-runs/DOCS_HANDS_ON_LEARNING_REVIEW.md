# Apollo11 docs: hands-on learning review and proposed changes

Date: 2026-10-05  
Review target: `/home/darshan/projects/apollo11-docs` at `b901a61802097c70570bd7b56f6303ce9e0816e1`  
Lab comparison: Apollo11 at `69113dcc80f77e32301d8ee7b9e73a67c923de96`  
Disposition: recommendations only; no course pages, lab implementations, or completion claims changed.

## 1. Recommendation

Make **Mission briefing → Concept chapters → Guided stage implementation → Mission debrief** the primary hands-on course. The learner should build the stage's resources, observe the mechanisms those resources activate, encounter a bounded failure, recover, and explain the result. Resource implementation is the stage itself, not “Exercise 1” after installing a finished stage.

The current docs offer a useful conceptual textbook and some worthwhile operational demonstrations. They do not consistently teach a beginner to implement the described system. Their recurring pattern is **read → deploy the finished snapshot → inspect → follow prescribed failure commands**. Explaining an installer’s internals does not give the learner the decisions, manifest relationships, or troubleshooting experience that the installer has already performed.

The Ignition crash example should be retained but rebuilt within that implementation journey. Its technical mechanism is useful: crashing the supervised server can cause a container restart while the Pod UID stays the same. The teaching gap is that learners apply the completed manifest, are told the conclusion, then collect the expected output. They have not constructed or investigated the process supervision that makes that result possible.

Do not solve this by renaming every “Exercise” to “Mission.” Change what the learner creates, decides, measures, and restores.

## 2. Scope and evidence boundary

This review covers:

- Course navigation, course contract, setup, mission briefings, and maintenance source map.
- All **41 implementation/investigation units** in Launchpad, Ignition, and Stages 1–7: respectively 5, 5, 5, 6, 4, 3, 5, 4, and 4. Stage 2's sixth unit is the appended canonical TLS lab.
- The **five status/audit investigations** in Stages 8–11 and the EKS appendix.
- All **six capstone missions**, its cleanup, and the conceptual assessment rubric.
- The headings and evidence/checkpoint sections of all **55 concept chapters**, with closer reads of chapters relevant to the gaps below. This is a learning-flow audit, not a claim that every explanatory sentence received a technical fact check.
- Source manifests, application contracts, script behavior, stage READMEs, and roadmap constraints where they affect the proposed learning path. Supporting source analysis is in [the lab cross-check](./LEARNER_FLOW_LAB_CROSSCHECK.md).

No cluster, Docker workload, cloud account, or failure experiment was run for this review. Findings about existing content and source relationships are static evidence. Proposed manual sequences, fixtures, and replacement lessons must pass a fresh learner-path lifecycle before publication. An existing verifier pass does not validate a newly written manual lesson.

References below link to local source files. The line references describe this checkout; they may move after edits.

## 3. Findings, ordered by impact

| Priority | Finding and evidence | Suggested change |
| --- | --- | --- |
| P0 | The course contract defines chapters as required and labs as optional; a reader can finish a stage without implementing it. The sidebar reinforces that split. [Course contract](../../apollo11-docs/docs/start/how-to-use-this-course.md), [sidebar](../../apollo11-docs/sidebars.ts). | Keep a clearly separate reading route, but make implementation required for hands-on mission completion. Label it “Build this stage,” explain the artifact learners will produce, and remove claims that conceptual answers alone complete the practical route. |
| P0 | Completed snapshots replace learner implementation. Stage 1 deploys with `apply.sh` and immediately runs 167 automated checks; Stages 3–6 similarly install then verify. [Stage 1](/home/darshan/projects/apollo11-docs/docs/stage-1.md:473), [Stage 3](/home/darshan/projects/apollo11-docs/docs/stage-3.md:314), [Stage 4](/home/darshan/projects/apollo11-docs/docs/stage-4.md:308), [Stage 5](/home/darshan/projects/apollo11-docs/docs/stage-5.md:325), [Stage 6](/home/darshan/projects/apollo11-docs/docs/stage-6.md:286). | Replace these sections with ordered resource construction and direct behavior checks. Move full installers/verifiers into a maintainer/reference appendix and an optional final audit. |
| P0 | Starting state and revision instructions conflict. Ignition names `143cac8…` plus a patch, while setup pins `69113dc…` with no patch. Setup calls Ignition's primary namespace `apollo-airlines`, but its Pod commands use `default`. Several later pages still describe an October candidate plus patch. [Ignition header](/home/darshan/projects/apollo11-docs/docs/ignition.md:9), [setup](/home/darshan/projects/apollo11-docs/docs/labs/setup.md:42), [Stage 5 boundary](/home/darshan/projects/apollo11-docs/docs/stage-5.md:497). | Establish one tested revision contract and one explicit stage boundary table. Include directory, context, namespaces, installed controllers, image tags, storage ownership, and baseline behavior for each entry. Remove contradictory patch instructions and stale pass-count assurances. |
| P1 | Important chapter topics have no corresponding learner implementation: configuration/identity and Jobs in Stage 1; active probe failure and resource/scheduling decisions in Stage 4; CI in Stage 5; dashboard and collection configuration in Stage 6; controlled measurement and manual HPA changes in Stage 7. | Add implementation milestones for each advertised practical outcome. See stage proposals below. Do not count a field in a prebuilt YAML file as a skill taught. |
| P1 | The approved progression and main lab flow diverge. Stage 5 puts Kustomize after Helm install/rollback, has no CI activity, and marks Argo CD optional. Stage 6 installs everything and visits traces before metrics. Stage 7 begins with enabled cache and combines scaling with scheduling. [Roadmap](../ROADMAP.md), [Stages 5–7](../../apollo11-docs/docs/stage-5.md). | Use Helm → Kustomize → CI/GHCR → Argo CD; metrics → dashboards → alerts/SLO → logs → traces → correlation; baseline → measurable cache → HPA → VPA. Place scheduling with Stage 4 as the target, while explicitly acknowledging any source implementation still residing in Stage 7. |
| P1 | Some “proofs” cannot distinguish the intended mechanism: Launchpad checks a seeded user after recreation, so reseeding could produce the same result; Stage 4 observes shutdown logs without measuring active request completion; PDB rejection relies on winning a race. [Launchpad persistence](/home/darshan/projects/apollo11-docs/docs/launchpad.md:505), [Stage 4](/home/darshan/projects/apollo11-docs/docs/stage-4.md:348). | Use a unique learner-created marker, recorded identities, bounded observation windows, controlled failure state, and a recovery check through the relevant endpoint or database. Narrow claims when adequate instrumentation is absent. |
| P1 | Command examples across concept chapters conflict with the stage labs/source: release names, HPA/VPA names, Redis kind, cache keys, Loki labels, and authenticated booking examples. See Section 8. | Audit every copyable command against its named snapshot. Separate conceptual pseudocode from runnable commands. Beginners should not have to guess whether a failure is their mistake or an illustration. |
| P2 | Predictions frequently give away the complete conclusion. Checkpoints mainly ask learners to repeat definitions. Full conceptual refreshers remain folded inside practical pages. | Put the question before the result, ask for a prediction and reasoning, then reveal expected evidence and interpretation separately. Replace redundant refreshers with chapter links and just-in-time field explanations. Assess a small independent adaptation at the end. |
| P2 | Future-stage pages turn reading status warnings and grepping repository text into “exercises.” [Stages 8–11](../../apollo11-docs/docs/stage-8.md), [EKS](../../apollo11-docs/docs/eks.md). | Keep these as honest roadmap/status pages. A repository-status audit is not a security/cloud implementation lab. Publish practical missions only when supported source and lifecycle evidence exist. |

## 4. Proposed course contract and implementation model

### 4.1 What a learner should experience

After a briefing and its concept chapters, the learner enters a guided construction sequence. Each milestone should contain:

1. **Intent:** an application problem and the behavior this step will enable.
2. **Decision:** which resource/field is appropriate and why; offer enough guidance for a beginner to answer.
3. **Artifact:** the exact learner-owned file to create or edit, referenced inputs, and a field-level scaffold.
4. **Apply:** the smallest meaningful resource group, with an explicit context and namespace.
5. **Observe:** API acceptance, controller progress, and real useful behavior; explain what each observation proves.
6. **Investigate:** an exact reversible failure within that milestone, with a question to answer from evidence.
7. **Recover:** restore the learner's saved configuration and prove useful behavior again.
8. **Explain:** relate the manifest field, responsible actor, observed change, and remaining limitation.

These are recurring parts of implementing the stage. They need not become eight repetitive headings on every page. Failure investigations stay in the journey because they expose the mechanism; optional challenges come after the learner has built a working stage.

A separate reading route can remain. Its completion is conceptual study, not completion of the hands-on implementation. Learner choice is compatible with clear outcomes.

### 4.2 “Implement all resources” without turning the course into transcription

Every resource in the stage must have a declared owner, purpose, introduction point, and evidence. That does not require beginners to hand-author several megabytes of Envoy Gateway CRDs or vendor RBAC.

| Resource category | Learner responsibility |
| --- | --- |
| New Apollo resource teaching this stage's concept | Construct it from a guided scaffold, choose the important fields, apply it, diagnose it, and prove behavior. |
| Previously learned Apollo resource | Reuse the learner's prior configuration or an explicitly identified known baseline; inspect any field changed by this stage. |
| Repeated application/database resources | Build one representative end to end; extend the pattern to the other components using a dependency/port/configuration table. Provide solutions separately. |
| Vendor controller/CRD bundle | Install the pinned supported bundle with a visible command, inspect controller/CRD readiness, then author the Apollo configuration it consumes. |
| Application source and SQL business logic | Supply the existing application and schema as inputs. Teach the Kubernetes wiring, not unrelated six-language implementation work. When caching or instrumentation is advertised as coding, add a separate explicit source-change milestone or narrow the outcome. |
| Maintainer installation/verification tools | Retain as reproducibility and regression tools. Do not make them a prerequisite for learner investigation. |

Use a learner directory ignored by Git, such as `learner-work/stage1/`, while keeping checked-in `stages/stage1/k8s/` as the reference solution. This is a proposed convention, not a directory currently supplied by the course. Give beginners a template with real schema structure, a short requirements table, staged hints, and a complete solution they can open if stuck. Do not use invalid placeholder YAML as an applyable starter.

Validate a learner artifact before applying it using rendering or an appropriate dry run. Explain that validation establishes a particular layer of acceptance; it does not prove runtime behavior. Avoid raw text `grep` as the primary check when resource kind/name matters.

### 4.3 Stage transitions and snapshot independence

Apollo11's source contract is independently runnable snapshots. The docs should not pretend stages are automatically cumulative in one live cluster. Nor should learners unknowingly retain stale resources from the preceding stage.

For each transition, document:

- What the previous mission left running and what evidence to save.
- Which namespaces, releases, controller resources, and storage are removed or retained.
- Whether this transition intentionally resets seeded data; no implied data migration.
- Which application source/images change and which learner manifests can be reused.
- The exact next baseline and a login/search check before introducing a new mechanism.

For early stages, reuse learned patterns in a clean stage workspace. For later stages, allow an explicitly scoped baseline bootstrap that installs **only already learned** mechanisms. It must not install the new mechanism the learner is about to implement. Where no such bootstrap exists, describe it as required lab work before publishing the new lesson.

The manual learning path and maintainer snapshot should have matching final resource intent, with documented exceptions for disposable diagnostic fixtures. Preserve the runnable snapshot while developing and validating its replacement, as the roadmap requires.

### 4.4 Scripts and direct evidence

`verify.sh` is not uniformly read-only. Depending on stage it also performs bookings, replacements, rollout failures, or other mutations. Calling it a harmless “baseline check” can perform the very investigation the learner was meant to conduct, and can change the evidence they expected to observe.

Use a short learner-authored evidence record instead: intended file/field, object condition, relevant event/log, observed request/row/metric, recovery, and explanation. Keep full automated verification optional at the end, disclose its mutations and prerequisites, and never use its pass count as the learner's completion rubric.

Infrastructure tooling such as `docker build`, `kind create cluster`, `kubectl apply`, `helm template`, `helm upgrade`, and `k6 run` is appropriate. The problem is delegating the new learning objective to a project-specific orchestration script. A build/load helper can remain for repetitive services after showing one build/load cycle and the frontend build-time URL contract. A safety/recovery helper can remain if learners still make the change and observe the mechanism themselves.

## 5. Stage-by-stage implementation proposals and existing-unit disposition

### 5.1 Launchpad — construct a runnable service graph

**Entry:** source checkout, Docker/Compose, local credentials. **Exit:** the ten-component airline is reachable, dependencies are understood, learner data survives container replacement, and cleanup ownership is clear.

Build one service image from the existing source while tracing its builder/runtime stages. Construct the Compose configuration incrementally: Identity database with init SQL and named volume; Identity service with runtime configuration and host mapping; Flight and Booking with their dependencies; Redis/Notification/Search; frontend with build-time API URLs. Extend the pattern across all ten components using a supplied contract table. Check the rendered model and meaningful endpoint after each group. Application implementation remains supplied.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Build and launch | Replace “run the finished Compose file” with incremental Compose construction. Explain each mount, environment input, network, port, and dependency condition as the learner adds it. Use `compose up` for the groups the learner has authored. |
| E2: Bridge networking/DNS | Integrate immediately after two services share a network. Compare host DNS, in-container DNS, and a downstream request; correct a wrong internal service URL in the learner file and recover. |
| E3: Dependency readiness | Keep, after the learner wires health/dependency settings. Record health/readiness and a real flight search before stopping Flight DB. Restore DB, then repeat the same useful request. Explain that Compose health alone does not remove host-published traffic. |
| E4: Persistence | Replace the seeded-user query with a unique inserted marker and record the named-volume identity. Remove/recreate the container while retaining the volume; query the marker, then delete only the marker. A reseeded admin row is insufficient proof. |
| E5: Read-only filesystem | Integrate while adding hardening to the learner Compose service. Inspect non-root identity, `read_only`, and `/tmp` tmpfs; test each location and remove scratch files. A filesystem error alone should not be confused with every security control. |

**Missing learning work:** building/configuring the image, explaining frontend build-time versus backend runtime configuration, establishing a manual login/search/booking/cancellation workflow, and verifying actual host/internal network boundaries. Retain the current reversible outage investigation rather than deleting it.

### 5.2 Ignition — author the request and investigate who repairs it

**Entry:** Docker, kind/kubectl, no Apollo Pod. **Exit:** a learner-authored HTTP Pod serves a known response; learner can distinguish container restart from Pod recreation and clean up their owned resources.

Construct a three-node kind configuration from a scaffold. Explain the port mappings needed later without turning future networking into today's objective. Identify nodes and system components. Generate Pod boilerplate locally, edit its container command to serve HTTP, add labels/restart policy, and apply the learner file. Verify HTTP before any failure. See Section 6 for a detailed replacement flow.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Provision cluster | Make this the first implementation milestone. Learner fills node roles and justified mappings, creates the cluster, and connects Docker containers to Kubernetes node/system evidence. |
| E2: Imperative/declarative | Fix the mismatch: `--dry-run` currently generates a file that is never used, then the docs apply the finished reference. Have the learner edit and apply the generated file, compare requested spec with assigned status, and explain local generation versus API submission. |
| E3: Evidence ladder | Integrate with the first deployment and every later failure. Ask which rung answers a specific question; avoid five commands as a memorized ritual. Use separate foreground port-forward and client terminals. |
| E4: Container crash/identity | Retain as an investigation of the Pod the learner created. Record UID, container ID, restart count, previous termination state, and HTTP before/after. Explain why the shell waits for `httpd`, how its exit ends the container, and why the kubelet reacts. |
| E5: Bare Pod deletion | Retain immediately afterward. Record owner references, delete the one named Pod, observe absence for a bounded interval, then recover using the learner manifest. Prove new UID and the HTTP response. Use this missing replacement mechanism to motivate Stage 1. |

Do not make unchanged Pod IP a required identity proof; use UID for object identity. Do not call a bare Pod universally “not production-ready” as the only lesson: identify precisely which owner/replacement guarantee this workload lacks.

### 5.3 Stage 1 — implement the ten-component Kubernetes baseline

**Entry:** healthy kind cluster; Ignition Pod removed deliberately. **Exit:** ten workload Deployments with Services, configuration, dedicated identities, three completed initialization Jobs, functional passenger workflow, and a diagnosed/recovered rollout failure.

Use this dependency order: Namespace → ConfigMap/Secret/ServiceAccounts → database and Redis Deployment/Service pairs → schema ConfigMaps and bounded Jobs → app Deployment/Service pairs → frontend and its build-time URLs. Teach one representative object of each new kind, then let the learner extend it. Use the source's actual paths and Job behavior, not an imagined generic directory structure.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Deploy | Replace the installer and verifier entirely in the main path with the resource sequence above. Show an image build/load before creating its Deployment. Wait and inspect at each dependency boundary. |
| E2: Ownership tree | Integrate when the learner creates the first Deployment. Follow Deployment → ReplicaSet → Pod; compare selector labels separately with owner references. |
| E3: Self-healing | Keep after two booking replicas and a working Service. Delete one named Pod, record new UID, wait for replacement endpoints, and repeat a useful request. Relate directly to Ignition's bare Pod result. |
| E4: Broken rollout | Keep, but first do a supported successful template update and inspect revision history. Then inject the invalid image, diagnose the newest failing Pod without fragile table parsing, measure continuing endpoint behavior, undo, and reconcile the learner file with the recovered image. |
| E5: `emptyDir` loss | Keep on an explicitly disposable database. Save the marker and schema evidence before replacement; show that the completed Job does not rerun. Recover by rerunning the proper bootstrap Job and verify the schema and application endpoint; lost marker remains lost. |

**Add:** a ConfigMap environment update showing existing processes retain old values until replacement; a missing required key reference exposing configuration failure; ServiceAccount token-mount inspection without printing secrets; Job logs/completion plus actual tables and seed rows; manual authentication and reversible booking. Keep experiments small so learners diagnose one changed relationship at a time.

### 5.4 Stage 2 — build the five-step access ladder

**Entry:** explicitly rebuild/reuse the known workload baseline in two namespaces; do not silently leave Stage 1's single-namespace deployment serving traffic. **Exit:** canonical Envoy/MetalLB routing with trusted local TLS and a working browser/API path.

This stage already has a good conceptual progression. Preserve it, but each step should change a learner-owned resource instead of running the full substage installer. Inspect controller installation separately from configuration.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| Substage 1: ClusterIP/DNS | Learner creates namespace-scoped Service definitions and a diagnostic client, tests short-name/FQDN resolution, traces ready EndpointSlices, then breaks/restores the selector. Recheck DNS during failure to separate name resolution from backend availability. |
| Substage 2: NodePort | Learner edits Service type/ports and relates nodePort to the kind mapping and targetPort. Query from the host and inside the cluster. Use a bounded wrong-targetPort investigation before restoring; show DNS can remain correct. |
| Substage 3: Ingress/TLS | Install pinned Traefik visibly, wait for readiness, author the IngressClass/Ingress configuration and TLS Secret wiring. Construct one route, extend it, then compare matching/wrong Host behavior. Certificate generation may use a disclosed helper after explaining its inputs, output Secret, namespace, and trust. |
| Substage 4: MetalLB | Install the vendor bundle, wait for webhook readiness, inspect the Docker subnet, then author IPAddressPool/L2Advertisement and change the proxy Service to LoadBalancer. Observe allocation and actual HTTP traffic. Do not hardcode the default subnet without validating it. |
| Substage 5: Gateway | Install pinned Envoy visibly; learner authors GatewayClass, EnvoyProxy linkage, listeners, routes, and attachment permissions. Read status per Gateway and per Route parent, then make real requests. Add bounded attachment/backend-reference failures and recovery. |
| Appended complete TLS lab | Move before the Stage 2 debrief/“continue” link and integrate with Substage 5. Learner wires certificateRefs, HTTPS routes, trusted curl, and frontend HTTPS API builds. Replace `verify-tls.sh` as the primary workflow with visible login/search/booking/cancellation steps. Keep that script as optional audit. |

**ReferenceGrant deserves special treatment:** the current frontend Route attaches across namespaces but references a backend in its own namespace. The provided grant can therefore exist without affecting that path. To teach enforcement, add a distinct temporary HTTPRoute in the apps namespace referencing the UI frontend Service: observe unresolved backend permission without the grant, add a narrowly scoped grant in UI, prove traffic, remove/recover, then clean up the temporary Route/grant. This is a proposed fixture needing source support and validation. Otherwise label the grant as reference-only and remove claims that the main path demonstrated it.

NetworkPolicy remains reference-only on kindnet. It must not be counted among enforced Stage 2 resources. Cross-namespace routing permission is not a substitute for RBAC or network isolation.

### 5.5 Stage 3 — connect identity, initialization, and persistent bytes

**Entry:** a clean known access/workload baseline with an explicit data reset boundary. **Exit:** all four stateful workloads use per-ordinal storage; the learner proves a unique marker survives Pod replacement on the same retained claim.

Build Identity DB first: headless Service → schema ConfigMap → StatefulSet `serviceName`, `volumeClaimTemplates`, mount, and `PGDATA` → observe claim provisioning → seed Job → normal client Service and Identity endpoint. Then extend to Flight, Booking, and Redis/AOF. Observe first-start and retained-data startup logs. Do not increase database replicas as a generic scaling challenge; replication is not implemented by merely changing a StatefulSet count.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Deploy/inspect storage | Replace installer/verifier with the construction sequence. Inspect StorageClass, scheduling, generated PVC and PV, Pod mount, tables, and app endpoint. `Bound` alone is not the completion criterion. |
| E2: Headless DNS | Integrate when wiring `serviceName`. Compare normal Service lookup with ordinal/headless lookup from a known diagnostic client; deliberately correct a wrong relationship and observe DNS after recovery. |
| E3: Persistence proof | Keep its unique marker. Add actual before/after Pod UID, PVC UID/name, PV binding, and mounted claim recording because the prose promises identity evidence the commands do not currently collect. Wait for the replacement object to exist before waiting for Ready. Query marker and delete it. |
| E4: Reclaim policy | Keep as inspection of the real application claims. If behavioral reclaim teaching is required, add a separate disposable scratch PVC/Pod fixture containing only a marker, delete that fixture, and audit PV/provisioner cleanup. Never turn application-PVC destruction into the normal lesson. |

**Add:** explain schema initialization versus seed Job ownership; rerun idempotent seed logic and inspect row-count stability; show logs distinguish first initialization from subsequent starts. Describe persistence as Pod-replacement persistence on node-local storage, not a node-loss restore or backup.

### 5.6 Stage 4 — make reliability settings produce observable decisions

**Entry:** Stage 3 behavior and storage established. **Exit:** learner-authored probes, requests/limits, termination settings, placement rules, priorities, and PDBs are connected to observable effects.

Introduce one reliability mechanism at a time on representative workloads before extending it. Use application dependency readiness for the real outage lab. Use disposable fixtures for liveness/startup/resource pressure where altering the real application cannot isolate a safe failure. Proposed fixtures must be committed and validated before docs claim them runnable.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Deploy/inspect governance | Replace with separate construction milestones: probes → resources/QoS → shutdown budget → priority/placement → PDB. Learner chooses values from a stated requirement and checks the resource that consumes each field. |
| E2: SIGTERM logs | Retain shutdown observation but narrow its claim. Record the old Pod's logs while it exists, endpoint transitions, replacement readiness, and a bounded traffic sample. To claim in-flight draining, add a supported controllable long-running request fixture and record whether that already-started request completes. A log saying “graceful” does not prove it. |
| E3: PDB eviction | Replace the “evict twice immediately” race with a controlled budget state: after proving two healthy replicas and one allowed eviction, deliberately scale the selected workload to one healthy replica, wait for `disruptionsAllowed=0`, request eviction and observe rejection, then restore two replicas and verify budget/traffic. Explain that scaling itself bypasses PDB protection and this proves budget enforcement in a known state, not concurrent-eviction timing. |

**Add required hands-on milestones:**

- Break one database dependency: readiness becomes false, relevant endpoint eligibility changes, liveness remains healthy, and restart count stays stable. Restore and prove useful behavior.
- In a disposable fixture, cause a bounded liveness failure and observe a restart. Contrast with readiness; do not make a transient DB outage the liveness trigger.
- Demonstrate startup gating on a controllable slow-start fixture; document its startup budget.
- Compare requested resources with scheduler placement/QoS. Use a disposable unschedulable Pod with an intentionally impossible request, inspect scheduling events, correct it, and clean it up. Do not create host-wide pressure to make a beginner observe OOM.
- Teach placement with taint/toleration, affinity, and topology as distinct decisions. Start with an ordinary disposable Pod that cannot enter a tainted node, then add permission/preference and inspect actual placement. Save/restore original node state.
- Inspect PriorityClass wiring. Only promise preemption behavior if a bounded resource-pressure fixture genuinely demonstrates it; higher integer priority by itself is configuration evidence.

Moving scheduling documentation to Stage 4 needs corresponding validated source work because the practical helper currently lives in Stage 7. Until then, mark the dependency explicitly; do not imply a relocation has already shipped.

### 5.7 Stage 5 — author delivery intent and follow it to runtime

**Entry:** a known workload/resource baseline with explicit release ownership. **Exit:** learner can construct parameterized packaging, compare overlay behavior, trace an image artifact, and observe GitOps ownership and recovery.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Helm rendering | Keep, but learner first templates a known booking Deployment/Service and creates dev/staging values, then compares exact rendered fields. Expand the existing chart pattern instead of transcribing bundled controllers. |
| E2: Helm install | Replace `apply.sh` with a visible chart install/upgrade after the learner inspects the render and hook/dependency requirements. Teach release metadata, hook Jobs, namespaces, and controller ownership. Avoid blindly having Helm adopt the preceding manually owned objects. |
| E3: Upgrade/rollback | Keep and add a meaningful supported configuration/image change alongside scale changes. Record actual history, recover to the prior good revision, and check the passenger workflow. Restore the learner's values file so the next upgrade does not recreate the unwanted change. |
| E4: Kustomize inspection | Move before CI/GitOps. Learner creates a base/overlay and changes one parameter already expressed through Helm, compares the same kind/name fields, and explains the different mechanisms. Render-only comparison is sufficient if clearly labeled; use a separate clean environment for optional deployment. |
| E5: Optional Argo CD drift | Make GitOps part of the required practical Stage 5 target. Install pinned Argo CD visibly, then author AppProject/Application source, destination, revision, permissions, and sync policy. Observe Synced versus Healthy, introduce one controlled drift, watch restoration, and clean up only owned applications. |

**Missing required CI milestone:** construct/explain the workflow from the repository's real `.github/workflows/main.yml`, show packaging checks and image build before registry publishing, and trace source revision → image reference/digest → running Pod. The source workflow targets Stage 5 images, so do not imply it automatically builds the latest Stage 7 code.

Provide two honest execution routes: a learner-owned GitHub fork/registry for an actual CI/GHCR run and promotion, and a local validation/build route for learners without an account. The local route teaches the artifact handoff but does not prove a remote workflow ran. No upstream commit/push access is required. External publication should be an explicitly chosen learner action.

A read-only upstream Argo CD drift demonstration can teach reconciliation without requiring a push. To teach Git-driven promotion, provide a learner-owned repository route and connect the Application to it. Clearly distinguish these outcomes and avoid letting multiple delivery tools manage the same resources concurrently.

### 5.8 Stage 6 — build one signal pipeline at a time

**Entry:** working airline with the Stage 6 instrumented application source, no new signal stack preinstalled. **Exit:** learner can construct discovery/collection configuration, query fresh data, show alert behavior, and correlate a real request.

The source already has an ordered implementation candidate in [SIGNALS.md](../stages/stage6/SIGNALS.md), `signals-lab.sh`, and the selector. Reuse its resource boundaries and recovery designs. Its own status requires a clean runtime lifecycle before replacing the previously verified full stack; do not mistake the existence of the selector for completed validation.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Full-stack deploy | Split into metrics, dashboards, alerts/SLO, logs, and traces. Install vendor operator/CRDs as supplied tooling; learner authors relevant ServiceMonitor, rules, datasource/dashboard configuration, Alloy pipeline, and Collector receiver/processor/exporter links. Use selected renders as inspected baseline/reference where needed, not automatic completion of every new mechanism. |
| E2: `trace-test.sh` | Replace primary execution with manual login, choose a real seeded flight, send a valid authenticated booking with trace context, capture response/request ID, query the trace, cancel the reservation, and check seat recovery. Keep script as optional regression audit. |
| E3: Grafana correlation | Keep, after learner-created datasources and known fresh traffic. Query actual Loki labels and Tempo trace; identify parent/child spans, the slow/error operation, and relevant logs. A pasted trace ID is only the start of the reasoning. |
| E4: PromQL | Move to the first metric milestone. Learner generates known traffic, examines raw samples, constructs rate/error/latency queries, and explains empty data versus zero values. Deliberately break/restore a monitor selector and distinguish target absence from failed scraping. |

Move the SLO hands-on section out of `learn/observability/queries-alerts-and-objectives.md` into the ordered Stage 6 implementation, keeping conceptual interpretation in the chapter. Replace one-shot `slo-lab.sh` execution with bounded manual traffic/failure observations and an available recovery helper.

**Required signal investigations:** remove/restore one ServiceMonitor and watch new samples; stop Grafana while metric storage remains accessible; induce valid failed booking attempts and inspect pending/firing/recovered alert state; pause Alloy and distinguish historical logs from fresh delivery; break the Collector exporter and distinguish successful bookings from missing new traces. Never delete telemetry PVCs to demonstrate delivery failure.

Record scrape, evaluation, export, and alert timing so “nothing yet” leads to bounded waiting and diagnosis. A short local run cannot prove a 28-day SLO. A recovered booking does not instantly erase failures from a rolling window.

### 5.9 Stage 7 — measure, then change one control

**Entry:** functioning Stage 6 telemetry and a seeded search workload. **Exit:** learner has comparable baseline/cache measurements, manually configured HPA behavior under load, and a justified VPA recommendation in Off mode.

| Current unit | Disposition and concrete replacement |
| --- | --- |
| E1: Deploy/cache headers | Start with fixed replica count and cache disabled, then run the measurement baseline. Enable the supplied cache implementation through learner configuration, use a controlled key for MISS→HIT→expiry, check TTL and response correctness, then repeat the same measured workload. Headers prove the branch, not improvement. |
| E2: Inspect HPA | Learner installs/inspects metrics-server and creates `search-hpa` only after CPU requests and metrics are understood. Predict a recommendation from measured usage, observe conditions and actual replica count, and explain caps/readiness/capacity. |
| E3: Automated scaling/scheduling | Remove `scaling-lab.sh run` from the learner path. Translate its load, HPA, observation, and recovery into discrete manual steps. Record original values, run bounded traffic, observe metrics → desired replicas → new Pods → ready endpoints, stop traffic, and observe scale-in. Scheduling belongs in Stage 4's target flow. |
| E4: VPA inspection | Provide a documented local values override enabling only Search VPA in Off mode; do not require deploying an entire staging/prod configuration just to see it. Inspect recommendations after enough samples, compare usage/requests, and prove VPA has not mutated the Pods. Validate the local override before publishing. |

Bring the existing [measurement chapter](../../apollo11-docs/docs/learn/scaling/measurement-baseline.md) and [k6 source guide](../stages/stage7/k6/README.md) into the main implementation flow. Keep fixed workload, correctness checks, seeded date, warm-up, replica count, route, and environment consistent. Report failure/no improvement honestly.

Separate the cache experiment from HPA: freeze autoscaling for the cache comparison, then restore/enable it for scaling. Avoid concluding that cache improvements came from added replicas. If a deliberately lower HPA threshold is needed on a laptop, explain it as a saved/restored demonstration setting, not a performance recommendation.

The current source supplies cache code. Change “implement cache-aside” to “configure and investigate Apollo's cache-aside implementation,” unless an explicit guided application-code implementation is added and validated.

### 5.10 Planned stages and EKS appendix

| Current investigation | Suggested disposition |
| --- | --- |
| Stage 8: find current gaps | Retain as a reference audit, remove hands-on security completion framing. The future implementation must build RBAC/PSA/hardening → enforcing Calico policy → Vault/ESO → Kyverno/Trivy/Cosign, proving positive and negative behavior. Token mounts alone are not security posture. |
| Stage 9: audit boundary | Retain as status/preparation. Future resources must be built incrementally with ownership/cost inventory and real cloud apply/inspect/break/recover/restore/destroy evidence. Do not produce runnable steps from untrusted legacy scaffolding. |
| Stage 10: inspect/classify/stop | Replace exercise styling with catalog status. Each later optional mission needs its own baseline, implementation, behavior, reversible failure, and cleanup. |
| Stage 11: verify catalog boundary | Same: roadmap/catalog, not a platform implementation activity. Future CRD/controller teaching must show actual reconciliation, not merely install a CRD. |
| EKS: read-only prototype investigation | Keep as research appendix with explicit trust limits. Reading Terraform does not complete EKS deployment or prove teardown. |

Conceptual security/cloud chapters can stay available, with examples clearly distinguished from implemented Apollo behavior. The required target path still extends through Stage 9, while the currently supported runnable local path ends at Stage 7. Both facts need to remain visible.

### 5.11 Capstone — demonstrate independent transfer

The existing capstone contains useful causal questions but repeats automatic setup, trace generation, and scaling. Replace its operational script tour with a requirements-driven assessment of the learner's known stage.

| Current mission | Suggested replacement |
| --- | --- |
| M1: establish Stage 7 with apply/verify | Learner establishes their implemented baseline and records release/configuration/revision ownership and meaningful endpoint evidence. A disclosed baseline bootstrap may support returning learners, but is not evidence that they implemented the course. |
| M2: trace-test script | Learner performs a booking/cancellation and locates its trace and logs themselves. Record correct response, database/application effect, trace context, and restored seat. |
| M3: database persistence | Keep the unique marker. Require UID/claim/binding/mount evidence as well as the row; restore baseline data afterward. |
| M4: cache and scaling orchestrator | Learner chooses a controlled measurement and manually demonstrates one scaling controller response. Keep cache effect, scheduling, and replica count conclusions separate. |
| M5: rollout sampler | Keep bounded traffic observation, but establish two healthy booking replicas **before** starting the sampler and ensure the full rollout falls within the observation interval. Timestamp each sample and record sampler termination. Do not credit Stage 4 preStop/PDB controls absent from this snapshot. |
| M6: controls versus plans | Keep the audit, correct the token-automount claim for the pinned source, and ask the learner to support each conclusion with their current render and runtime. |

Add one independent adaptation: for example, create a new supported route to an existing Service with its own hostname and working TLS, or change a values-driven replica policy and explain its controller effects. Supply requirements and hints, not a turnkey script. Verify the result, cause one narrowly scoped failure, restore, and prove behavior. Do not introduce an entirely new service/API as an assessment prerequisite.

Keep the conceptual causal rubric, but score practical evidence separately from an “imagined request.” Hands-on completion should require an artifact, a diagnosis, a recovery, and an explanation.

## 6. Worked replacement: Ignition's implementation journey

This is an editorial blueprint, not a newly validated runnable lesson.

### Step 1 — request a cluster

After the briefing/chapters, ask: “We need one control-plane node and two workers. Which nodes will run the scheduler and kubelets? What disappears if the Docker host disappears?” Provide a kind configuration scaffold and explain its required networking fields. Learner writes it, creates the cluster, explicitly selects/checks the disposable context, and identifies nodes/system Pods.

**Evidence:** Ready node conditions, assigned roles, Docker node containers, and system component names. **Limit:** three containers on one host do not prove host availability.

### Step 2 — request one HTTP process

Generate local boilerplate with `kubectl run … --dry-run=client -o yaml` and edit that file. Explain which fields the generator did not supply for this application. Have the learner add labels, explicit restart policy, a server command, and the container port.

Supply and explain the small BusyBox command block rather than asking a Kubernetes beginner to invent process supervision. It creates `/www/index.html`, starts `httpd` in the background, captures its PID, and waits for that PID. When the child is killed, the shell finishes; this ends the container and makes the restart policy relevant. Without that relationship, killing an arbitrary child while PID 1 continues running would not demonstrate kubelet container restart.

Apply the learner file, inspect the requested spec versus assigned status, wait for Ready, then run port-forward in a dedicated foreground terminal and curl from a second terminal. Explain that `containerPort` documents a port; port-forward provides this client access path.

**Evidence:** API object exists, node assignment, startup log, expected HTTP body. **Limit:** Ready without a probe is not an HTTP test.

### Step 3 — investigate one crash

Ask before showing the answer: “If we kill the HTTP server, what does the shell do? Which Kubernetes actor has enough information to react? Will the API object need a new UID?”

Record a table before failure:

| Signal | Before | After |
| --- | --- | --- |
| Pod UID | learner records | learner records |
| Container runtime ID | learner records | learner records |
| Restart count | learner records | learner records |
| Previous termination state | learner records | learner records |
| HTTP body/status | learner records | learner records |

Use one exact command targeting this Pod's `httpd`. Do not hide every command error under `|| true`: identify the expected exec interruption, and diagnose “no process found” or unrelated failures. Watch until the container identity/restart count has changed; an immediately successful Ready wait can otherwise observe the old condition before the crash is processed. Inspect previous container logs/termination details and repeat HTTP. Restart the port-forward if it exited.

**Interpretation revealed afterward:** same Pod UID, new container execution, increased restart count, restored server response. The kubelet restarted the container within the existing Pod. It did not recreate the deleted HTTP child while leaving the shell untouched, and it did not create a new Pod object.

### Step 4 — remove the desired Pod object

Inspect owner references and record UID. Ask: “What durable resource still asks for this Pod after deletion?” Delete only the named Pod, observe absence for a stated bounded interval, and explain why that observation agrees with the missing controller owner. Do not rely on “no resources in default” because unrelated Pods may exist.

Recover by applying the learner-authored file. Wait for the object and readiness; record its new UID and repeat HTTP. Compare the crash and deletion rows side by side. A new Pod may reuse an IP, so UID remains the reliable object distinction.

### Step 5 — adapt and debrief

Require one small independent change: recreate the bare Pod from the learner file with a different served message, explaining why its command change requires recreation rather than an arbitrary live Pod edit. Prove the new response. Ask what additional resource would maintain replicas after deletion; Stage 1 implements that answer.

**Completion:** authored configuration and manifest; a working HTTP endpoint; evidence-backed restart/recreation comparison; recovery from both events; owned-Pod/port-forward cleanup; explicit retain/delete cluster instructions for the next mission.

This keeps the original educational distinction while making it the result of a system the learner understands and builds.

## 7. Proposed page structure and concept-to-build mapping

Keep the sidebar order: briefing, concept chapters, then implementation. Rename the final page label to “Build Ignition,” “Build Liftoff,” etc.; move reference installers out of the main steps. Remove the top “jump to investigations” shortcut as the main emphasis and link instead to the first construction milestone.

Each briefing should list the concrete artifacts and behaviors learners will produce. Each concept chapter should end with “You will use this to…” and a link to the relevant implementation milestone. The chapter explains the mechanism; the implementation page gives the full stage/context-dependent command sequence.

| Chapters | Implementation destination |
| --- | --- |
| Container process/image, images/configuration | Build image; author runtime/build configuration; inspect running artifact. |
| Container networks, state/dependencies | Compose network and port wiring; named-volume marker; DB outage and recovery. |
| Cluster API/components/lifecycle | kind config; learner Pod; API/spec/status distinction; crash/deletion comparison. |
| Ownership, Services, config/identity, Jobs, rollout, ephemeral state | Stage 1's dependency-ordered resource construction and recovery. |
| CNI, Service control/data path, DNS, NodePort/LB, Ingress/TLS, Gateway | Stage 2 ladder with real routing, trust, attachment, and backend-permission evidence. |
| Storage lifetimes, claims, headless identity, operations, init/seed, recovery | Stage 3 StatefulSets/claim mounts, initialization, idempotency, unique-marker proof. |
| Probes, termination, resources, scheduling, PDB | Stage 4 independent controller/kubelet/scheduler/Eviction API investigations. |
| Helm, Kustomize, CI, GitOps, promotion | Stage 5 learner packaging and visible artifact/reconciliation handoffs. |
| Metrics, discovery, queries/SLO, logs, traces, correlation | Stage 6 six ordered signal milestones. |
| Measurement, cache, HPA, VPA/capacity | Stage 7 controlled experiment and manually observed controller responses. |
| Security/cloud | Planned chapters until a trusted runnable implementation exists. |
| Booking-through-Kubernetes | Capstone causal explanation supported by the learner's real workflow. |

Re-home imperative multi-step mutation examples currently embedded in “Evidence and limits,” including storage replacement/scale-down, Kustomize apply, and SLO/benchmark runs. A chapter example should either be obviously non-executable illustration or identify its exact runnable prerequisite. The course currently says chapter commands are examples, yet some of them deliberately mutate/delete workloads; this ambiguity undermines the starting-state contract.

## 8. Reproducibility corrections to make alongside the rewrite

These are examples identified from static comparison, not an exhaustive validated command inventory. Check every runnable block during the rewrite.

| Source location | Problem | Required correction |
| --- | --- | --- |
| [Ignition header](/home/darshan/projects/apollo11-docs/docs/ignition.md:9), [setup](/home/darshan/projects/apollo11-docs/docs/labs/setup.md:123), stage boundary footers | Old hash/patch instructions disagree with the pinned no-patch source. | One revision contract, no stale candidate language, stage-specific truthful lifecycle evidence. |
| [Setup namespace table](/home/darshan/projects/apollo11-docs/docs/labs/setup.md:65) | Ignition grouped with `apollo-airlines`, although Pod commands have no namespace and use `default`. | Declare `default` explicitly for Ignition or introduce a consistently supported owned namespace. |
| [Stage 1 installer table](/home/darshan/projects/apollo11-docs/docs/stage-1.md:482) | Generic config paths do not reliably match the actual source tree. | Link each exact file/group after inspecting the stage, rather than describing an invented directory layout. |
| [Launchpad E4](/home/darshan/projects/apollo11-docs/docs/launchpad.md:505) | Existing seeded row is indistinguishable from reinitialization. | Insert/delete a unique marker and record volume identity; wait for DB readiness before the post-recreate query. |
| [Service evidence](/home/darshan/projects/apollo11-docs/docs/learn/workloads/services-and-readiness.md:83) | Runs curl inside frontend although its Dockerfile supplies an NGINX runtime and does not install curl. | Use an explicitly provisioned diagnostic client or a documented host port-forward. Do not assume tools inside app images. |
| [Configuration evidence](/home/darshan/projects/apollo11-docs/docs/learn/workloads/configuration-and-identity.md:108) | Required missing ConfigMap/key references generally prevent startup; the text suggests empty/stale values merely from applying the object late. | Separate missing required input, optional reference, and unchanged environment in an already-running process. |
| [Delivery evidence chapters](/home/darshan/projects/apollo11-docs/docs/learn/delivery/rendering-and-helm.md:75), [GitOps](/home/darshan/projects/apollo11-docs/docs/learn/delivery/gitops-and-ownership.md:87) | Use `apollo-airlines` release/Application names versus the stage lab's `apollo11` release and `apollo11-dev` Application. | Use snapshot-specific names throughout or explicitly label generic examples. Include isolated GitOps destination namespaces. |
| [Logs](/home/darshan/projects/apollo11-docs/docs/learn/observability/logs.md:70) | LogQL uses `app="booking"`; source Alloy relabels the app label into `service`. | Use emitted labels such as `service="booking"` and a real request/trace ID. [Alloy source](../stages/stage6/helm/apollo11/templates/observability/loki/alloy.yaml). |
| [Trace evidence](/home/darshan/projects/apollo11-docs/docs/learn/observability/traces.md:82) | Booking example uses nonexistent sample ID, wrong body field, no auth, assumed `X-Trace-Id`, and an unexplained localhost Tempo listener. | Use real seeded ID, source `flightId` body, bearer token, explicit `traceparent`, known trace ID, actual Tempo service/forwarded port, and cancellation. [Trace source workflow](../stages/stage6/scripts/trace-test.sh). |
| [Cache evidence](/home/darshan/projects/apollo11-docs/docs/learn/scaling/cache-aside.md:53) | Addresses Redis as a Deployment; uses `route:` key, fixed old date, `departure`/`arrival` parameters, obsolete localhost NodePort, and an unquoted query URL. | Use StatefulSet/Pod Redis, actual `search:<origin>:<destination>:<date>` key, seeded date, `origin`/`destination`, quoted URL, and the named current access path. [Search implementation](../stages/stage7/code/search/main.go). |
| [HPA](/home/darshan/projects/apollo11-docs/docs/learn/scaling/hpa.md:77), [VPA](/home/darshan/projects/apollo11-docs/docs/learn/scaling/vpa-and-capacity.md:56) | Query `search` rather than `search-hpa`/`search-vpa`; default dev has no VPA. | Match template names; provide the validated local VPA Off override and warm-up expectations. [Autoscaling templates](../stages/stage7/helm/apollo11/templates/autoscaling). |
| [Termination evidence](/home/darshan/projects/apollo11-docs/docs/learn/reliability/termination-and-draining.md:83) | `logs --previous` fetches a prior container execution in the same Pod, not a deleted Pod after replacement. Logs alone cannot confirm request draining. | Collect the old Pod logs while it exists, distinguish restart from replacement, and narrow/measure the draining claim. |
| [PDB exercise](/home/darshan/projects/apollo11-docs/docs/stage-4.md:389) | Immediate second eviction may succeed after fast recovery. | Demonstrate a known observed zero budget with a controlled replica state, or build a validated fixture that holds a replacement unready. Restore and prove traffic. |
| [Canonical TLS](/home/darshan/projects/apollo11-docs/docs/stage-2.md:637) | New required TLS material sits after the debrief/next-stage link and calls verification automation for the transaction. | Integrate into the Gateway build before completion; manually demonstrate trusted workflow and recovery. |
| [Capstone M5](/home/darshan/projects/apollo11-docs/docs/capstone.md:214) | A 15-second nominal sampler can finish while terminal 2 is still scaling to two replicas, before the rollout under test. | Establish healthy replicas first, synchronize sampler/start of rollout, sample through rollout completion with a bounded maximum, and retain timestamps. |
| [Capstone M6](/home/darshan/projects/apollo11-docs/docs/capstone.md:270) | Claims the current Stage 7 snapshot does not prove planned token control while the pinned chart explicitly disables automount. | Separate the implemented token setting from absent Stage 8 enforcement/hardening; inspect actual current render/runtime. |

Review expected errors as carefully as successes. An arbitrary curl failure is not proof of NetworkPolicy enforcement, TLS rejection, cache fallback, or HPA input failure. State the specific failure evidence and the control check that excludes other causes. For future NetworkPolicy teaching, use a correct namespace-qualified destination and a protocol-appropriate client, not an HTTP request to a short database name in the wrong namespace.

## 9. Implementation backlog

### Phase A — establish the new contract and pilot Ignition

**Docs changes:** `start/how-to-use-this-course.md`, `labs/setup.md`, `index.md`, Ignition briefing/implementation, `sidebars.ts`, and maintenance source-map/content-migration records. Align the revision and namespace contract. Add a resource/artifact map and the guided Ignition sequence from Section 6. Retain chapter explanations and the reference manifest.

**Lab changes:** establish an ignored learner-work convention and any starter assets needed; preserve original runnable files/scripts. No new app code is required for the basic Ignition distinction because the existing server supervision supports it.

**Acceptance:** a learner starting from a clean checkout authors the configuration/Pod, observes HTTP, completes both failure/recovery paths without using `verify.sh`, and explains the different identities. A maintainer separately runs regression verification.

### Phase B — rewrite Launchpad and Stages 1–3

Publish dependency tables and resource scaffolds; replace turnkey installation as the teaching path; supply manual passenger workflow; fix the persistence marker; implement the complete Stage 2 ladder/TLS and either validate the ReferenceGrant fixture or mark it reference-only.

Document every stage transition and storage cleanup boundary. Verify final manual resources against source intent rather than assuming differently named learner files are equivalent.

### Phase C — supply missing behavior in Stage 4

Implement and validate the deterministic PDB sequence, bounded probe/resource fixtures, and any shutdown instrumentation necessary for the selected claim. Move scheduling into the target stage only with compatible source support. A documentation-only rewrite cannot create missing observability or guarantees.

### Phase D — align Stages 5–7 with the approved progression

Add actual packaging authoring, CI and GitOps routes; validate ordered Stage 6 selection, then expose manual configuration and fresh signal evidence; consolidate SLO and baseline material into the implementation pages; split the HPA load experiment from scheduling and provide a lightweight local VPA path.

### Phase E — rewrite the capstone and future-stage framing

Use independent adaptation and evidence assessment. Keep unsupported stages as plans, retain correct trust warnings, and move installation/verification references out of the primary learning path. Correct stale names/commands across concept and reference pages.

This review does not propose replacing source code based on docs text. Source behavior and the roadmap govern supported mechanisms. Needed new fixtures/manual paths are explicit lab-development work, followed by docs that teach the validated behavior.

## 10. Publication and learner-completion criteria

Before marking a rewritten stage ready:

- Run the **documented learner commands from a clean start**, using learner artifacts rather than the completed snapshot installer. Confirm every prerequisite is introduced and every resource reference resolves.
- Complete apply → inspect → break → recover → teardown, checking behavior and owned residue. Run maintainer regression verification separately; report what each path validates.
- Verify the stage transition into the next baseline, including image/source differences, namespace/release ownership, and data-reset expectations.
- Test interruption recovery for failures/load generators and verify restoration of original settings. Save recovery before inducing a failure.
- Review every advertised practical concept against an artifact and observable outcome; mark inspection-only or reference-only concepts honestly.
- Compile/typecheck the docs and check links/anchors. These establish publication integrity, not Kubernetes behavior.
- Have a learner follow the pilot and record where they needed the solution. If that review has not happened, report it as missing evidence rather than calling the course beginner-validated.

Assess hands-on mission completion using a compact evidence record:

| Dimension | Required evidence |
| --- | --- |
| Build | Learner file or values/template change and the reason for its important fields. |
| Observe | API/controller status plus an actual request, row, sample, trace, or denied action that answers the intended question. |
| Diagnose | Evidence locating the controlled failure at the correct layer; no blind full reinstall. |
| Recover | Restored configuration and useful behavior, with temporary changes/markers removed. |
| Explain | Resource → responsible actor → observed effect → boundary the mechanism does not cover. |
| Transfer | One small supported adaptation completed from requirements with hints available. |

**Suggested starting point:** pilot Ignition end to end, then apply the same construction/evidence standard across Launchpad and Stages 1–7. This is a sequence for implementation, not permission to stop after renaming the exercise headings.
