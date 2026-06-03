---
title: Stage 5 - Payload Integration
description: Helm charts, Kustomize overlays, and GitHub Actions for automated deployments
---

# Stage 5 — Payload Integration

Package all stage4 manifests as a **Helm chart** with **Kustomize overlays** for dev/staging/prod environments. Add **GitHub Actions** for CI/CD.

## What's New

### Helm Chart

Structure:
```
helm/apollo11/
├── Chart.yaml              # chart metadata
├── values.yaml             # default config (dev)
├── templates/
│   ├── _helpers.tpl        # label/selector helpers
│   ├── _resources.tpl      # ns/sa/priorityclass helpers
│   ├── configmap.yaml      # ConfigMap + Secret
│   ├── config/namespace.yaml # namespaces, SAs, PriorityClass, init scripts
│   ├── infra/
│   │   ├── postgres.yaml   # 3 postgres StatefulSets + headless SVCs
│   │   └── redis.yaml      # catalog-redis + notification-redis StatefulSets
│   ├── apps/
│   │   ├── auth.yaml       # auth Deployment + Service
│   │   ├── catalog.yaml    # catalog Deployment + Service
│   │   ├── circulation.yaml # circulation Deployment + Service
│   │   ├── notification.yaml # notification Deployment + Service
│   │   └── fines.yaml      # fines StatefulSet + headless Service
│   ├── ui/
│   │   └── frontend.yaml   # frontend Deployment + Service + Ingress
│   └── jobs/
│       └── init.yaml       # init-auth-db, init-catalog-db, init-circulation-db Jobs
```

### Kustomize Overlays

```
overlays/
├── base/           # references helm templates as base
├── dev/            # 1 replica, dev image tag :dev
├── staging/        # 2 replicas, latest tag
└── prod/           # 3 replicas, v1.0.0 tag, pod disruption budget
```

### Values Architecture

```yaml
# All values templated — change in values.yaml or overlays
image:
  repository: apollo11
  tag: latest

apps:
  auth:
    replicas: 2
    port: 8080
    resources:
      requests: {cpu: 50m, memory: 64Mi}
      limits:   {cpu: 500m, memory: 256Mi}

postgres:
  auth:
    storage: 1Gi
    resources:
      requests: {cpu: 50m, memory: 128Mi}
      limits:   {cpu: 500m, memory: 512Mi}

probes:
  startup:   {periodSeconds: 5, failureThreshold: 6}
  liveness:  {initialDelaySeconds: 15, periodSeconds: 10, failureThreshold: 3}
  readiness: {initialDelaySeconds: 5, periodSeconds: 5, failureThreshold: 3}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Stage5 Architecture                                             │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Helm Chart (values.yaml)                                 │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│  │  │ Dev Overlay  │  │ Stage Overlay │  │  Prod Overlay │  │   │
│  │  │  replicas=1  │  │  replicas=2  │  │  replicas=3  │  │   │
│  │  │  tag=:dev    │  │  tag=:latest  │  │  tag=:v1.0.0 │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  kubectl apply -k overlays/{env}                          │   │
│  │  OR                                                       │   │
│  │  helm template apollo11 | kubectl apply -f -             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Kubernetes Cluster                                       │   │
│  │  apollo11-infra / apollo11-apps / apollo11-ui            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```bash
# Render helm template (dry run)
helm template apollo11 helm/apollo11/

# Install with defaults (dev)
helm install apollo11 helm/apollo11/ -n apollo11 --create-namespace

# Install with staging overrides
helm install apollo11 helm/apollo11/ \
  --set apps.auth.replicas=2 \
  --set image.tag=latest

# Kustomize build (dev)
kubectl kustomize overlays/dev/

# Kustomize apply (dev)
kubectl apply -k overlays/dev/

# ArgoCD sync (see stage5 GitOps flow)
argocd app sync apollo11-dev
```

## Files

```
stage5/
├── code/                     # same as stage4 (probe handlers)
│   ├── auth/main.py
│   ├── catalog/main.go
│   ├── circulation/main.go
│   ├── notification/main.go
│   ├── fines/main.go
│   └── frontend/main.go
├── helm/apollo11/            # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── overlays/
│   ├── base/                 # kustomization base
│   ├── dev/                  # 1 replica, dev tag
│   ├── staging/             # 2 replicas
│   └── prod/                # 3 replicas, stricter limits
└── README.md (this file)
```

## What's Next
Stage6 adds **observability** — Prometheus metrics, Grafana dashboards, Loki for logs, and OpenTelemetry for distributed tracing.