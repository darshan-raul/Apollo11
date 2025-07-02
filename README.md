# Apollo11

![logo](./images/apollo11-project-logo.png)

11 stage plan to enable you to become very good with the whole k8s based cloud native ecosystem and comfortable with all the components involved for almost every requirement that may come up to build a robust architecture.

![tools](./images/apollo11-flavor2-project.drawio.png)

## Stages


### 🚀 **Liftoff** — Containers & Local Development

> *"Ignition begins with understanding containers."*

- ✅ Intro to containers & Docker
- ✅ Docker CLI, Dockerfiles, Images, Volumes
- ✅ Build & Run multi-service apps via Docker Compose
- Local workflows with `tilt` or `skaffold` for developer productivity

---

### 🧱 **Stage 1: It Begins** — Kubernetes Barebones

> *"Get it off the ground using the simplest cluster."*

- ✅ Setup Kind Cluster
- ✅ Deploy simple nginx via `kubectl`
- ✅ Create basic `Deployment`, `Service`, and use `Namespaces`
- View underlying ReplicaSets, simulate pod failure, do one roll out and rollback
- RollOut Vs Recreate
- kubectl walkthrough + jsonpath parsing

---

### 🧠 **Stage 2: Structural Integrity** — Best Practices

> *"Harden the fundamentals."*

* ConfigMaps, Secrets
* Labels, Annotations
* Selectors
* Init containers, sidecars
* Probes: Readiness, Liveness, Startup
* MaxUnavailable and MaxSurge
* minReadySeconds,,terminationGracePeriodSeconds
* Resource requests/limits, Quotas
* Restart policies
* Scheduling: Taints/Tolerations, Node Affinity, Pod Affinity/Anti-Affinity
* SecurityContext & PodDisruptionBudgets

---

### 💾 **Stage 3: Persistent Journey** — Storage Deep Dive

> *"Save state and survive reboots."*

* Downward API
* Persistent Volumes & Claims
* Storage Classes
* StatefulSets
* Volume Modes & Access Modes
* Reclaim Policies (Retain, Delete, Recycle)
* CSI Drivers (brief intro)

---

### 🌐 **Stage 4: Orbit Control** — Networking in Depth

> *"Achieve stable orbit with secure comms."*

* Cluster Networking 101
* Services: ClusterIP, NodePort, LoadBalancer
* Ingress Controllers & TLS Termination
* NetworkPolicies
* CoreDNS config
* Gateway API (replacing Ingress)
* Intro to Service Mesh (Linkerd or Istio lite)

---

### 📦 **Stage 5: Modular Payloads** — Packaging and Extensibility

> *"Standardize and ship the system."*

* Helm Charts (create and use)
* Kustomize for environment-based configs
* Intro to Operators
* Custom Resources / CRDs
* Helmfile / GitOps bundling patterns

---

### 🔎 **Stage 6: Mission Control** — Monitoring & Debugging

> *"Keep eyes on every subsystem."*

* `kubectl debug`, `ephemeral containers`
* CrashLoopBackOff
* Headlamp or Lens UI
* Metrics Server, API metrics
* Prometheus + Grafana + P99 + SRE monitoring
* Loki for logs
* Tempo/Jaeger for traces
* OpenTelemetry overview

---

### 🔁 **Stage 7: Flight Automation** — CI/CD and Workflows

> *"Smooth deployment across galaxies."*

* Jobs and CronJobs
* GitOps vs traditional CI/CD
* Argo Workflows / Tekton Pipelines
* ArgoCD for GitOps deployment
* Multi-env deploys via Helmfile / ArgoCD apps
* Event-driven pipelines

---

### 🔐 **Stage 8: Secure Docking** — Kubernetes Security

> *"Protect your capsule at all costs."*

* TLS/SSL & Cert Manager
* Sealed Secrets / External Secrets
* RBAC (basic to advanced)
* Service Accounts
* Vault for secrets management
* OPA / Kyverno for policies
* Keycloak for SSO / OIDC
* Tools: Kubescape, Trivy, Polaris

---

### 📈 **Stage 9: Adaptive Thrust** — Autoscaling & Optimization

> *"Match thrust with need."*

* Horizontal Pod Autoscaler (HPA)
* Vertical Pod Autoscaler (VPA)
* Cluster Autoscaler
* Karpenter (modern autoscaling)
* QoS Classes
* Load Testing (k6, vegeta)
* Pod Priority & Preemption

---

### 💥 **Stage 10: Contingency Mode** — Backup, Upgrades, Chaos

> *"Prepare for failure and return."*

* Backup & Restore using Velero/Rook
* Blue/Green and Canary upgrade patterns
* Minor/Major cluster version upgrades
* topologySpreadConstraints
* Pod Distrubtion Budgets
* Chaos Engineering with LitmusChaos / ChaosMesh

---

### 🌍 **Stage 11: Earth Departure** — Production-Grade Clusters

> *"Beyond the test lab."*

* CI/CD integration: GitHub Actions to push images
* Use GCR, ECR, Harbor (with pull secrets)
* IaC with Terraform/Pulumi for cluster setup
* Cluster hardening guides (NSA/CIS Benchmarks)
* Multi-cluster and Federation basics

---

### 🪐 **To Mars** — Advanced Delivery & Operations

> *"Progressive delivery and self-reliance."*

* CRDS
* Operators
* Argo Rollouts for Canary/Blue-Green
* Feature Flags
* Progressive Delivery strategies
* Harbor – self-hosted registry with security scanning
* Cluster cost analysis (Kubecost)
* Platform Engineering intro (Backstage, Crossplane)
* Multi-tenant Kubernetes



## Prerequisites

- This course assumes that you come with bare basic knowledge about k8s concepts. 
- I highly recommend this playlist, will cover everything you ever need to know [varjosh k8s course](https://youtube.com/playlist?list=PLmPit9IIdzwRjqD-l_sZBDdPlcSfKqpAt&si=TN-MJ8-1pKj1_V4J)
    - Its long so you can choose what you need, if you are a complete beginner i would encourage to go through all of it from start to end


## Tools

| Category | Tools |
|---|---|
| Backend API |  Golang,Python |
| Sql Database| Postgres,Mysql |
| Nosql Database | MongoDB | 
| Local Development | Tilt |
| Dashboard | Headlamp,k9s |
| Container Management | Docker, Podman |
| CI | Github Actions |
| GitOps | ArgoCD |
| Progressive Deployment | Argo Events, Argo Rollouts |
| Secret Store | Vault |
| Ingress Controller | Apisix |
| Packaging | Helm |
| Patching | Kustomize |
| Logging | Fluentd (agent), Loki (backend) |
| Service Mesh | Istio |
| Monitoring | Prometheus, Grafana |    
| Compliance Monitoring | kubebench |
| Policy Engine | OPA/Kyverno |
| Policy Checker | Kubescape |
| Backup and Restore | Velero |
| Load Testing | hey,Kube-monkey |
| Cluster Provisioning | Kubespray (optional) |
| Serverless | OpenFaas |
| Container Builds | Buildah |

Extra:

- https://github.com/groundcover-com/caretta
- Dapr
- Dagger