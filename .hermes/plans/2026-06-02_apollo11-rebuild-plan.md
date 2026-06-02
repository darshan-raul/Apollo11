# Apollo11 Rebuild Plan — "New Foundation"

## Goal

Rebuild Apollo11 as a clean, self-contained learning bootstrap with **working code for every service**, **complete manifests for every stage**, and **automated tests** that verify the learner completed each stage correctly.

---

## Current State (Reference Material Only)

The existing repo provides:
- A well-designed 11-stage curriculum with clear learning objectives
- 7 Dockerfiles (stub or real, need audit)
- Partial k8s manifests in stages 1, 2, 3, 5, 11
- A `devbox.json` with local toolchain
- `prep.sh` for environment setup
- A `code/k8s/` directory referencing services that may be stubs

**What does NOT exist:**
- Stages 4, 7, 8, 9, 10 — completely empty directories
- Source code for the 7 microservices (only Dockerfile stubs or empty dirs)
- GitHub Actions workflows (stage 5 references them but no `.github/workflows/`)
- ArgoCD Application manifests
- Any test infrastructure
- `agents.md` — until now

---

## Design Principles

1. **Every stage is independently verifiable** — there's a test or checklist at the end of each stage that proves the learner did it right
2. **Working code, not pseudo-code** — every microservice is a real, runnable app with a working Dockerfile
3. **Progressive disclosure** — early stages use imperative `kubectl` commands before introducing declarative manifests; Helm comes only at stage 5
4. **No cloud dependency until stage 9** — all stages 1-8 use local k3d/kind; cloud (EKS/GKE/AKS) only in stage 9
5. **Devbox as the only env requirement** — `devbox install` must get you everything needed for local stages

---

## Proposed Stage Redesign

### Phase 0: Foundation
- **Launchpad** — Docker, Dockerfiles, Docker Compose, YAML primer
- **Ignition** — kind/k3d, kubectl basics, first Pod, imperative vs declarative

### Phase 1: Core Workloads
- **Stage 1** — Deployments, ReplicaSets, Jobs, CronJobs, ConfigMaps, Secrets
- **Stage 2** — Networking: Services (ClusterIP, NodePort, LoadBalancer), Ingress, DNS-based service discovery
- **Stage 3** — Persistent Storage: PVCs, PersistentVolumes, StorageClasses, StatefulSets, emptyDir, hostPath

### Phase 2: Operational Excellence
- **Stage 4** — Probes, resource requests/limits, QoS classes, PodPriority, resource quotas
- **Stage 5** — Packaging: Helm charts, Kustomize overlays, GitHub Actions CI/CD, ArgoCD GitOps
- **Stage 6** — Observability: Prometheus, Grafana, Loki, OpenTelemetry, logs + metrics + traces correlation

### Phase 3: Scaling & Reliability
- **Stage 7** — HPA, taints/tolerations, node affinity, pod affinity/anti-affinity, topology spread
- **Stage 8** — Security: RBAC, SecurityContexts, Pod Security Admission, OPA/Kyverno, Vault, Sealed Secrets, cert-manager, Trivy scanning
- **Stage 9** — Cloud: EKS/GKE/AKS via Terraform, Cluster Autoscaler/Karpenter, k6 load testing, PDBs, cluster upgrades, HA design

### Phase 4: Advanced & Production
- **Stage 10** — Service mesh (Linkerd), Argo Rollouts, DevSecOps pipeline, Velero backup, Chaos Mesh
- **Stage 11** — CRDs/Operators, k3s homelab, KEDA, Backstage, Goldilocks/Kubecost, Crossplane, Knative, Datree, Falco, Cluster API

---

## Implementation Order

### Step 1: Audit existing code/manifests
Determine what's real vs stub in `code/docker/` and `code/k8s/`. Audit each Dockerfile, service impl, and k8s manifest.

**Files to inspect:**
- `code/docker/*/Dockerfile` (all 7)
- `code/k8s/*/main.py` or `main.go` (if they exist)
- `stages/stage*/**/*.yaml`

### Step 2: Define the 7 microservices (contracts)
Write a minimal but working version of each:
- `portal` — Node/React, serves static + calls backend API
- `core-api` — Python/FastAPI, orchestrates other services
- `notification-service` — Python/FastAPI, simple POST/GET endpoints
- `payment-api` — Go, handles payment requests (stub logic)
- `quiz-service` — Go, serves quiz questions
- `report-generator` — Go binary, CronJob, generates a text report
- `backup-service` — Go binary, CronJob, "backs up" (touches a file)
- `postgres` — stock PostgreSQL 15, initialized via init SQL script

Each service needs:
```
code/
  {service}/
    Dockerfile          # multi-stage build
    go.mod / requirements.txt  # dependency file
    main.go / main.py   # actual source
    *.go / *.py         # handlers, models, etc.
    README.md           # what this service does
    test/
      *_test.go / test_*.py
```

### Step 3: Write stage materials (per stage)

For each stage, create:

1. **`stages/stageN/README.md`** — Learning objectives, concepts covered, what to do, expected outcome, verification checklist
2. **`stages/stageN/EXERCISE.md`** — Step-by-step exercise with exact commands to run
3. **`stages/stageN/solutions/`** — Reference YAML manifests (only for the instructor/reviewer, not shown to learner initially)
4. **`stages/stageN/test/`** — Automated test script (shell script or Python) that verifies the stage was completed correctly
5. **`stages/stageN/cleanup.sh`** — How to tear down this stage's resources

### Step 4: Define the test infrastructure

A `test/` directory at root with:
```
test/
  runner.sh              # runs all stage tests in order
  stage1_test.sh         # verifies pods are running, etc.
  stage2_test.sh         # verifies services are reachable, ingress works
  ...
  util/
    kubectl_helper.sh    # shared helpers
    k8s_assert.sh        # assertion functions
```

Tests use `kubectl` and `curl` — no special framework needed for k8s verification.

### Step 5: Refactor devbox.json

Add all tools that appear in the curriculum:
- Add: `k9s`, `tilt`, `kind`, `kustomize`, `k6`, `trivy`, `opa`, `kyverno` (or note these as container-based)
- Consolidate to a single `devbox.json` at root
- Remove duplication — currently `devbox.json` at root AND the project references a separate one

### Step 6: Create CI/CD scaffolding

- `.github/workflows/ci.yml` — runs stage tests on every PR
- `.github/workflows/stage-test.yml` — reusable workflow that takes `stage` as input

### Step 7: Update prep.sh

Make `prep.sh` idempotent and able to run from any directory. Add a `--verify` flag that checks all tools are installed.

### Step 8: Write the top-level README

Single-page overview that:
- Explains what Apollo11 is
- Shows the stage map (with status badges)
- Links to each stage's README
- Shows the prerequisites
- Explains the tools ecosystem

---

## Key Files to Create / Modify

### New files to create:
```
AGENTS.md                           # (already created)
stages/stage4/README.md
stages/stage4/EXERCISE.md
stages/stage4/test/stage4_test.sh
stages/stage4/solutions/*.yaml
stages/stage7/...                   (all missing stages)
stages/stage8/...
stages/stage9/...
stages/stage10/...
test/
  runner.sh
  util/
test/stage1_test.sh
test/stage2_test.sh
... (one per stage)
/.github/workflows/
  ci.yml
  stage-test.yml
code/
  [each service with real implementation]
```

### Files to refactor:
```
devbox.json          # consolidate tools
prep.sh              # add --verify, idempotency
stages/stage1/        # complete the partial work
stages/stage2/        # complete
stages/stage3/        # complete
stages/stage5/        # add GitHub Actions, ArgoCD
stages/stage6/        # add k8s manifests for Prometheus/Grafana
stages/stage11/       # complete
```

### Files to delete (stale reference material):
```
stages/stage5/helm/instructions.md   # replace with proper stage5 materials
```

---

## Risks & Tradeoffs

| Risk | Mitigation |
|---|---|
| Rebuilding all 7 microservices from scratch is a lot of code | Focus on minimal-viable implementations — each service needs only 50-100 lines of real code |
| 11 stages × 4-5 files each = 44-55 new files | Use templating/boilerplate for manifests; only the exercise content is novel per stage |
| Tests for k8s stages are brittle | Use idempotent `kubectl` assertions (`kubectl wait`, `kubectl get` checks only) |
| User may want to keep current stage artifacts | Keep `stages/` content as solutions reference; rebuild stage directories fresh with exercise-first approach |
| Devbox package availability varies | Some tools (Kyverno, OPA, Karpenter) are better run as k8s add-ons, not local packages — clarify in docs |

---

## Open Questions

1. **Source language preference?** Currently Go + Python. Stick with that or simplify to just one?
2. **Learner verification model:** Do you want self-check (learner runs test script) or automated CI-gated progression (must pass test to unlock next stage)?
3. **Should each stage be a git branch?** Allows clean PR review per stage, but adds workflow complexity.
4. **Do you want a "coach" mode** where there's an AI agent that can answer questions per stage?
5. **Helm chart ownership:** Should the Helm chart be the "gold standard" that all stages converge toward, or a separate artifact introduced at stage 5 only?

---

## Next Actions

1. **Confirm** the proposed stage redesign (Phase 0-4) matches your intent
2. **Decide** on the open questions above
3. **Choose** whether to proceed with a subagent-driven build (delegate microservices to parallel agents) or sequential build
4. **Start** with Step 1 (audit existing code) to establish ground truth