---
title: "Ignition — First Kubernetes Cluster"
description: "Launch a kind cluster and run your first Pod. Learn kubectl, cluster architecture."
---

# Ignition — First Kubernetes Cluster

**Goal:** Spin up a local Kubernetes cluster using kind, verify it works, and launch your first Pod.

## What You'll Learn

- Launch a kind cluster and understand its components
- Use `kubectl` for inspection, apply, and deletion
- Imperative vs declarative resource management
- Cluster architecture overview (control plane, data plane, etcd, CNI)
- Pod manifest structure and fields
- Why Pods are fragile and need higher-level abstractions

## Steps

### 1. Create cluster

```bash
kind create cluster --name apollo11
kubectl cluster-info
kubectl get nodes
```

### 2. Inspect the cluster

```bash
kubectl get componentstatuses    # scheduler, etcd, controller-manager
kubectl api-resources            # all available resource types
```

### 3. Run your first Pod imperatively

```bash
kubectl run apollo-shell --image=alpine --restart=Never -- sh -c "echo 'hello from k8s'"
kubectl get pods
kubectl logs apollo-shell
kubectl exec apollo-shell -- cat /etc/os-release
```

### 4. Write a Pod manifest (declarative)

```yaml
# stages/ignition/pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: apollo-shell
  labels:
    app: shell
    stage: ignition
spec:
  containers:
    - name: shell
      image: alpine:latest
      command: ["sh", "-c", "echo 'hello from k8s' && sleep 3600"]
      resources: {}
```

```bash
kubectl apply -f pod.yaml
kubectl describe pod apollo-shell
```

### 5. Clean up

```bash
kubectl delete pod apollo-shell
kind delete cluster --name apollo11
```

## Key Concepts

```
Kind cluster architecture:
┌─────────────────────────────────────┐
│  Control Plane Node (kind-control)  │
│                                     │
│  ┌─────────┐  ┌───────────────┐   │
│  │ kube-   │  │ kube-controller│   │
│  │ apiserver│ │ -manager      │   │
│  └────┬────┘  └───────┬───────┘   │
│       │               │            │
│  ┌────▼───────────────▼──────┐    │
│  │        etcd               │    │
│  └───────────────────────────┘    │
│                                     │
│  ┌─────────┐  ┌───────────────┐   │
│  │ kubelet │  │ CNI (bridge)  │   │
│  └─────────┘  └───────────────┘   │
└─────────────────────────────────────┘
```

| Component | What it does |
|---|---|
| kube-apiserver | REST API entry point for all cluster operations |
| etcd | Distributed key-value store for cluster state |
| kube-controller-manager | Runs controllers (replication, endpoints, etc.) |
| kube-scheduler | Assigns Pods to nodes based on resources |
| kubelet | Agent on each node, ensures containers are running |
| CNI | Network plugin (bridge/host-local/etc.) |

## What's Next

Once the cluster is verified working, move to **Stage 1** where all application services are deployed declaratively using Deployments.