# Application Overview

This document provides a current overview of the applications within the Apollo 11 project, located in `code/k8s`.

## Service Summary

| Service Name | Type | Tech Stack | Kubernetes Resource | Exposure | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Portal** | Frontend | Node.js / React (Vite) | Deployment | NodePort (3000:80) | Main user interface for the platform. |
| **Core API** | Backend | Python / FastAPI | Deployment | ClusterIP (8087:8000) | Central API gateway and orchestration service. |
| **Notification Service** | Microservice | Python / FastAPI | Deployment | ClusterIP (8001:8000) | Handles system notifications. |
| **Payment API** | Microservice | Go | Deployment | ClusterIP (8083:8080) | Manages payment processing. |
| **Quiz Service** | Microservice | Go | Deployment | ClusterIP (8082:8080) | Manages quiz content and logic. |
| **Report Generator** | Job | Go | CronJob | N/A | Generates periodic reports. |
| **Backup Service** | Job | Go | CronJob | N/A | Performs database backups. |
| **Postgres** | Database | PostgreSQL 15 | StatefulSet | ClusterIP (5432) | Primary data store for all services. |

## Source Code Locations

All source code is located within the `code/k8s` directory:

- `code/k8s/core-api`
- `code/k8s/notification-service`
- `code/k8s/payment-api`
- `code/k8s/quiz-service`
- `code/k8s/portal`
- `code/k8s/jobs/report-generator`
- `code/k8s/jobs/backup-service`

## Kubernetes Configuration

The Kubernetes manifests are located in `stages/stage5/kustomization`.

- **Base Configurations**: `stages/stage5/kustomization/base` (contains individual service definitions)
- **Overlays**: `stages/stage5/kustomization/overlays` (environment-specific configurations, e.g., `dev`)
