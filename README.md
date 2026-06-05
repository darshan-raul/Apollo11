# Apollo11

![logo](./images/apollo11-project-logo.png)

**Apollo Airlines** — A cloud-native flight management system built across 13 stages, teaching you the full Kubernetes ecosystem from Docker Compose to custom operators.

![tools](./images/apollo11-flavor2-project.drawio.png)

---

## 🛫 The Application: Apollo Airlines

A flight reservation platform with 6 services and 4 infrastructure components:

| Service | Tech | Role |
|---|---|---|
| identity | Python/FastAPI | JWT auth, passenger profiles |
| flight | Go/Gin | Flight inventory, seat management |
| booking | Go/Gin | Reservations (flagship workflow) |
| search | Go/Gin | Flight search |
| notification | Go/Gin | Event fan-out |
| frontend | React (Tailwind CSS) | SPA |

**Infrastructure:** 3 PostgreSQL databases + 1 Redis

The **flagship workflow** — create a booking — spans 4 services and generates a distributed trace that students observe in observability tools:

```
Frontend → Booking Service → Identity Service
                        → Flight Service (get flight)
                        → Flight Service (decrement seats)
                        → Booking DB
                        → Notification Service
```

---

## Stages

### 🧱 Launchpad – Docker Compose ✅ [📖 README](stages/launchpad/README.md)

* ☑️ Learn what **Docker** is, why it exists, and how it solves the problem of environment consistency.
* ☑️ Understand containers conceptually and how they differ from virtual machines.
* ☑️ Write **Dockerfiles** and build container images using best practices and layering principles.
* ☑️ Use **Docker Compose** to run and wire together multiple containers locally.
* ☑️ Learn **YAML** syntax and structure as the foundation for Kubernetes configuration files.
* ☑️ Verify all services have `/healthz`, `/readyz`, `/metrics` endpoints
* ☑️ Modern React/Tailwind CSS frontend with environment-based API configuration

---

### 🔥 Ignition – First Kubernetes Cluster ✅ [📖 README](stages/ignition/README.md)

* ☑️ Launch a local Kubernetes cluster using **kind** and understand what components are created.
* ☑️ Use core **kubectl** commands to inspect, apply, modify, and delete Kubernetes resources.
* ☑️ Understand the difference between **imperative and declarative** resource management in Kubernetes.
* ☑️ Get a high-level overview of Kubernetes cluster architecture, with concepts that will be revisited in depth later.
* ☑️ **Launch your first Pod** and understand the structure and fields of a Pod manifest YAML.
* ☑️ Learn why Pods are fragile and why higher-level workload abstractions are required.

---

### Stage 1 : 🚀 Liftoff – All Workloads on Kubernetes ☐ [📖 README](stages/stage1/README.md)

* ☐ Organize workloads using **namespaces** and understand logical isolation within a cluster.
* ☐ Deploy applications using **ReplicaSets** and **Deployments** and understand their reconciliation behavior.
* ☐ Launch and manage multiple deployments simultaneously on the cluster.
* ☐ Access running workloads using **port forwarding** for local testing and debugging.
* ☐ Run one-time and scheduled tasks using **Jobs** and **CronJobs**.
* ☐ Externalize configuration using **ConfigMaps** and understand when to use them.
* ☐ Manage sensitive data securely using Kubernetes **Secrets**.
* ☐ Design multi-container Pods using **init containers and sidecars** to support application behavior.

---

### Stage 2 : 🧭 Guidance, Navigation & Control – Networking ☐ [📖 README](stages/stage2/README.md)

* ☐ Understand Kubernetes **DNS** and how **service discovery** works inside the cluster.
* ☐ Learn how Pods communicate with each other and **what networking guarantees Kubernetes requires**.
* ☐ Expose applications using **Services** and understand ClusterIP, NodePort, and LoadBalancer types.
* ☐ Control network traffic using **NetworkPolicies** to enforce isolation and security.
* ☐ Route external traffic into the cluster using **Ingress resources** with **Traefik**.
* ☐ Understand the role of **kube-proxy** and how CNI plugins implement pod networking.
* ☐ Use the **Gateway API** as a modern, extensible alternative to traditional Ingress.

---

### Stage 3 : 💾 Mission Data – Persistent Storage ☐ [📖 README](stages/stage3/README.md)

* ☐ Use ephemeral storage options like **emptyDir** and **hostPath** and understand their limitations.
* ☐ Learn what **Persistent Volumes** are and how storage is abstracted in Kubernetes.
* ☐ Understand **reclaim policies** and how Kubernetes handles storage after workloads are deleted.
* ☐ Request storage using **Persistent Volume Claims** and see how binding works.
* ☐ Use **StorageClasses** to define dynamic provisioning behavior for storage.
* ☐ Expose Pod and node metadata to applications using the **Downward API**.
* ☐ Run stateful applications using **StatefulSets** and understand their guarantees.

---

### Stage 4 : 🎛️ Flight Control Systems ☐ [📖 README](stages/stage4/README.md)

* ☐ Configure **liveness**, **readiness**, and **startup probes** to control workload health.
* ☐ Define **resource requests** and **limits** to manage CPU and memory consumption.
* ☐ Understand **Quality of Service (QoS) classes** and how Kubernetes prioritizes Pods under pressure.
* ☐ Control scheduling behavior using **Pod Priority** and **Preemption**.
* ☐ Enforce fair usage and prevent resource exhaustion using **resource quotas**.
* ☐ Use **PodDisruptionBudgets** for safe cluster operations.

---

### Stage 5 : 📦 Mission Payload Integration – Packaging ☐ [📖 README](stages/stage5/README.md)

* ☐ Package and template Kubernetes manifests using **Helm charts**.
* ☐ Customize Kubernetes configurations using **Kustomize overlays and patches**.
* ☐ Build **CI/CD pipelines** to test and deploy applications automatically using **GitHub Actions**.
* ☐ Implement **GitOps** workflows using **Argo CD** to manage deployments declaratively.

---

### Stage 6 : 📡 Mission Operations – Observability ☐ [📖 README](stages/stage6/README.md)

* ☐ Collect and query metrics using **Prometheus**.
* ☐ Visualize metrics and build dashboards using **Grafana**.
* ☐ Centralize logs using **Loki** and correlate them with metrics.
* ☐ Trace requests across services using **OpenTelemetry**.
* ☐ Debug using distributed traces.
* ☐ Use **DaemonSets** to deploy monitoring and system agents on every node.
* ☐ use **kubeshark** to analyze packets
* ☐ Debug running Pods using **ephemeral containers** without restarting workloads.

---

### Stage 7 : 🛰️ Orbital Maneuvering – Scaling ☐ [📖 README](stages/stage7/README.md)

* ☐ Automatically scale workloads using **Horizontal Pod Autoscaler (HPA)**.
* ☐ Control where Pods run using **taints and tolerations**.
* ☐ Influence scheduling decisions using **node affinity rules**.
* ☐ Control Pod co-location and separation using **pod affinity and anti-affinity**.
* ☐ Add **Redis caching** to the Search service (TTL 5min)

---

### Stage 8 : 🔐 Command Module Hardening – Security ☐ [📖 README](stages/stage8/README.md)

* ☐ Implement fine-grained access control using **Role-Based Access Control (RBAC)**.
* ☐ Secure Pods using **SecurityContext** (runAsNonRoot, readOnlyRootFilesystem).
* ☐ Use **hardened container images** to minimize the attack surface.
* ☐ Authenticate workloads using **Service Accounts**.
* ☐ Store and manage secrets securely using **Vault** as an external key store.
* ☐ Enforce baseline security standards using **OPA Gatekeeper** or **Kyverno**.
* ☐ Scan container images using **Trivy**.

---

### Stage 9 : 🌕 Lunar Orbit – Cloud Deployment ☐ [📖 README](stages/stage9/README.md)

* ☐ Deploy Kubernetes clusters on **EKS** and **GKE** using **Terraform**.
* ☐ Scale cluster nodes dynamically using **Cluster Autoscaler**.
* ☐ Load test applications using **k6** to validate performance.
* ☐ Distribute workloads evenly using **topology spread constraints**.
* ☐ **Perform safe Kubernetes cluster upgrades**.
* ☐ Protect availability during disruptions using **Pod Disruption Budgets**.
* ☐ Design and operate a **truly highly available Kubernetes cluster**.

---

### Stage 10 : 🧪 Mission Extensions ☐ [📖 README](stages/stage10/README.md)

* ☐ Hook into Pod and container lifecycle events using **lifecycle hooks**.
* ☐ Implement a **service mesh** using **Linkerd** for traffic management and security.
* ☐ Perform **progressive deployments** using **Argo Rollouts**.
* ☐ Build a full **DevSecOps pipeline** integrating security into delivery.
* ☐ Implement backup and restore strategies using **Velero**.
* ☐ Introduce controlled failures using **Chaos Mesh** to test resilience.

---

### Stage 11 : 🚀 Towards Mars ☐ [📖 README](stages/stage11/README.md)

* ☐ Design and implement custom **CRDs** and **Kubernetes operators**.
* ☐ Extend the Kubernetes API server with custom functionality.
* ☐ Build a **homelab using k3s** and expose services securely.
* ☐ Implement event-driven autoscaling using **KEDA**.
* ☐ Build internal developer platforms using **Backstage**.
* ☐ Analyze and optimize cluster costs using **Kubecost**.
* ☐ Manage clusters declaratively using **Cluster API**.

---

## Prerequisites

- Basic knowledge of Linux (command line, file system, environment variables)
- Docker installed and running (`docker --version`)
- No prior Kubernetes experience required

---

## Getting Started

### 1. Install Devbox

```bash
curl -fsSL https://get.jetify.com/devbox | bash
```

### 2. Set Up Environment

```bash
devbox shell  # loads all tools defined in devbox.json
```

### 3. Tools Installed

| Tool | Purpose |
|---|---|
| docker | Container runtime |
| kubectl | Kubernetes CLI |
| kind | Local k8s clusters |
| k3d | Alternative local k8s |
| helm | Chart packaging |
| kustomize | Config patching |
| skaffold | Local dev pipelines |
| k9s | Terminal dashboard |
| terraform | Cloud provisioning |
| argocd | GitOps deployment |
| k6 | Load testing |
| trivy | Image scanning |
| opa | Policy engine |

### 4. Start with Launchpad

```bash
cd stages/launchpad
docker compose up
```

---

## Project Structure

```
Apollo11/
├── SPEC.md                   # Full API contracts, service schemas, endpoints
├── README.md                 # This file
├── AGENTS.md                 # Agent context for AI assistants
│
├── stages/
│   ├── launchpad/            # Docker Compose — 10 components, stub code
│   │   ├── README.md
│   │   ├── docker-compose.yml
│   │   └── code/             # identity, flight, booking, search, notification, frontend
│   │
│   ├── ignition/             # kind cluster, first Pod, kubectl basics
│   │   └── README.md
│   │
│   ├── stage1/               # K8s: Deployments, ConfigMaps, Secrets, Jobs
│   │   ├── README.md
│   │   ├── k8s/
│   │   ├── scripts/
│   │   └── code/
│   │
│   ├── stage2–stage11/       # (scope defined in SPEC.md)
│   │
└── test/                     # Automated verification scripts per stage
```

Each stage is independently runnable. Each stage's `code/` directory is a self-contained snapshot that copies the previous stage's code and adds its additions.

---

## Code Evolution

| Stage | What Changes |
|---|---|
| Launchpad | Stub code with `/healthz`, `/readyz`, `/metrics`, structured logging. Frontend: React/Tailwind CSS with VITE env vars for API URLs. |
| Stage 1–3 | k8s manifest evolution only, code unchanged |
| Stage 4 | Add `/healthz/startup`, `/healthz/live`, `/healthz/ready` handlers + SIGTERM graceful shutdown. Frontend: Go stub replaced with React/Tailwind app. |
| Stage 5 | Packaging only, code unchanged |
| Stage 6 | Full `/metrics` + OTEL SDK integrated |
| Stage 7 | Search gets Redis caching (X-Cache header) |
| Stage 8 | Non-root Dockerfiles, service accounts |
| Stage 9 | Cloud provisioning, code unchanged |
| Stage 10 | Service mesh + progressive delivery |
| Stage 11 | CRD operator, KEDA autoscaling |

---

## Seed Data (Always Present)

**Airports:** BOM, DEL, SIN, DXB, LHR, JFK

**Flights (today + 30 days):** AA101, AA102, AA201, AA202, AA301, AA401

**Users:**
- `admin@apolloairlines.com` / `admin123` (ADMIN)
- `passenger@apolloairlines.com` / `pass123` (PASSENGER)

---

## Tools

| Category | Tools |
|---|---|
| Frontend | React, Tailwind CSS, Vite |
| Backend API | Golang, Python |
| SQL Database | PostgreSQL |
| NoSQL Database | Redis |
| CI | GitHub Actions |
| GitOps | ArgoCD |
| Progressive Deployment | Argo Rollouts |
| Secret Store | Vault |
| Ingress Controller | Traefik |
| Packaging | Helm |
| Patching | Kustomize |
| Logging | Fluentd, Loki |
| Service Mesh | Linkerd |
| Monitoring | Prometheus, Grafana |
| Policy Engine | OPA |
| Backup and Restore | Velero |
| Load Testing | k6 |
| Cluster Provisioning | Terraform |
| Chaos Engineering | Chaos Mesh |
| Autoscaling | HPA, VPA, KEDA |
| Custom Controllers | Kubernetes Operators |