# Apollo 11 Helm Chart Instructions

This directory contains the Helm chart for deploying the Apollo 11 microservices stack.

## Prerequisites

- Kubernetes cluster (e.g., kind, k3d, minikube)
- Helm installed (`helm`)

## Structure

```
helm/
├── apollo11/         # The Helm Chart
│   ├── charts/
│   ├── templates/    # Kubernetes Manifest Templates
│   ├── Chart.yaml    # Chart Metadata
│   └── values.yaml   # Default Configuration Values
└── instructions.md   # This file
```

## Usage

### 1. Install the Chart

To install the chart with the release name `apollo11` in the `apollo11` namespace:

```bash
helm install apollo11 ./apollo11 --namespace apollo11 --create-namespace
```

### 2. Verify Installation

Check the status of the pods:

```bash
kubectl get pods -n apollo11
```

### 3. Customize Configuration

You can override default values using the `--set` flag or by providing a custom values file:

```bash
helm install apollo11 ./apollo11 -n apollo11 --set portal.service.nodePort=30001
```

### 4. Upgrade the Chart

If you make changes to the chart or values, upgrade the release:

```bash
helm upgrade apollo11 ./apollo11 -n apollo11
```

### 5. Uninstall

To remove the installation:

```bash
helm uninstall apollo11 -n apollo11
```
