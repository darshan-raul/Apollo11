---
title: "Stage 1: Liftoff — Kubernetes workloads and configuration"
description: "Deploy Apollo Airlines with Deployments, Services, ConfigMaps, Secrets, ServiceAccounts, and Jobs, then diagnose and roll back a failed rollout."
---

# Stage 1: Liftoff

**Goal:** Move the ten-component Apollo Airlines baseline into Kubernetes,
inspect the controllers and configuration that keep it running, and recover
from both Pod loss and a failed rolling update.

Ignition ended with a bare Pod that stayed deleted. Stage 1 adds the first
controller-owned workloads and stable Service endpoints:

```text
Deployment --> ReplicaSet --> Pod replicas
     |                         ^
     +-- desired template      | labels
                               |
Service -----------------------+ selector
```

## What you will learn

1. Deployments, ReplicaSets, Pod templates, labels, and selectors
2. ClusterIP and NodePort Services plus EndpointSlices
3. Namespaces, ConfigMaps, Secrets, and dedicated ServiceAccounts
4. One-shot database initialization Jobs
5. `emptyDir` as Pod-scoped, ephemeral storage
6. rollout status, ReplicaSet history, failure diagnosis, and rollback

Stage 1 uses raw Kubernetes manifests as the learning surface. The top-level
`kustomization.yaml` is retained as a reproducible composition file, but
Kustomize itself is compared with Helm in Stage 5.

## Architecture

```text
Namespace: apollo-airlines

  configuration                         stable networking
  +---------------------+               +--------------------+
  | ConfigMap + Secret  |-------------->| app containers     |
  | 13 ServiceAccounts  |               | 10 Services        |
  +---------------------+               +--------------------+

  infrastructure Deployments            application Deployments
  identity-db  x1                        identity      x2
  flight-db    x1                        flight        x2
  booking-db   x1                        booking       x2
  redis        x1                        search        x2
                                          notification  x2
  initialization Jobs                     frontend      x2
  init-identity-db
  init-flight-db
  init-booking-db
```

The databases intentionally use `emptyDir`. Data survives a container restart
inside the same Pod, but it is lost when that database Pod is replaced. Stage 3
introduces StatefulSets and persistent volumes to change that boundary.

## Prerequisites

- Complete Ignition using `stages/ignition/kind-config.yaml` or its single-node
  alternative. The host port mappings in those configs are required for the
  NodePort exercises.
- Keep Docker, kind, kubectl, curl, and jq available.
- Run commands from the repository root.

Confirm the intended cluster before mutating it:

```bash
kubectl config current-context
kubectl get nodes
```

The context must be `kind-apollo11` or `kind-apollo11-dev`.

## Build

### 1. Read the declared state

Start with the namespace and one application path:

```bash
sed -n '1,120p' stages/stage1/k8s/config/namespace.yaml
sed -n '1,180p' stages/stage1/k8s/apps/booking/booking-dep.yaml
sed -n '1,100p' stages/stage1/k8s/apps/booking/booking-svc.yaml
```

Trace these exact relationships:

- the Deployment selector equals the Pod-template label;
- the Service selector equals that same label;
- the Service's `targetPort` equals the container port; and
- the Pod template names the dedicated `booking` ServiceAccount.

If any selector differs, Kubernetes accepts the YAML but traffic or ownership
breaks. Syntax validation alone cannot prove this relationship.

### 2. Build and apply

The ordered script builds the six application images, loads them into the
selected kind cluster, and applies configuration → infrastructure → Jobs →
applications. It waits at every dependency boundary.

```bash
bash stages/stage1/scripts/apply.sh
```

Reuse already loaded images with:

```bash
bash stages/stage1/scripts/apply.sh --skip-build
```

For the single-node cluster, either make that context current or pass it:

```bash
bash stages/stage1/scripts/apply.sh --context kind-apollo11-dev
```

The equivalent all-at-once render is useful for static inspection:

```bash
kubectl kustomize stages/stage1/k8s >/tmp/stage1-rendered.yaml
kubectl apply --dry-run=client -f /tmp/stage1-rendered.yaml
```

The ordered script remains the trusted live-install path because it proves the
databases are available before starting their Jobs.

## Inspect

### 1. Follow ownership and reconciliation

```bash
kubectl get deployments,replicasets,pods -n apollo-airlines
kubectl describe deployment booking -n apollo-airlines
kubectl get pods -n apollo-airlines -l app=booking --show-labels
kubectl get replicaset -n apollo-airlines -l app=booking \
  -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,OWNER:.metadata.ownerReferences[0].name'
```

The Deployment owns a ReplicaSet; the ReplicaSet owns the Pods. That ownership
chain is why the controller can replace a deleted Pod.

### 2. Follow a Service selector to ready endpoints

```bash
kubectl get service booking -n apollo-airlines -o wide
kubectl get endpointslice -n apollo-airlines \
  -l kubernetes.io/service-name=booking -o wide
kubectl get pods -n apollo-airlines -l app=booking -o wide
```

The EndpointSlice addresses must match ready booking Pods. A Service is stable
as its backing Pod IPs change.

### 3. Inspect configuration without leaking values

```bash
kubectl describe configmap apollo-airlines-config -n apollo-airlines
kubectl describe secret apollo-airlines-secrets -n apollo-airlines
kubectl get deployment booking -n apollo-airlines \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{" <- "}{.valueFrom.configMapKeyRef.name}{.valueFrom.secretKeyRef.name}{"\n"}{end}'
```

A Secret separates sensitive values from the Pod template, but it is not
automatically encrypted merely because Kubernetes represents it as base64.
Stage 8 adds an external secret lifecycle and observable rotation.

### 4. Inspect workload identity

```bash
kubectl get serviceaccounts -n apollo-airlines
kubectl get pod -n apollo-airlines -l app=booking \
  -o jsonpath='{.items[0].spec.serviceAccountName}{"\n"}'
kubectl auth can-i get pods \
  --as=system:serviceaccount:apollo-airlines:booking \
  -n apollo-airlines
BOOKING_POD=$(kubectl get pod -n apollo-airlines -l app=booking \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n apollo-airlines "$BOOKING_POD" -- \
  test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token
```

Expected results are the identity `booking`, an authorization answer of `no`,
and a successful final `test`. Applications receive distinct identities but
do not need Kubernetes API access, so token automount is disabled. Stage 8
later introduces Roles and RoleBindings where API access is actually needed.

### 5. Inspect one-shot Jobs

```bash
kubectl get jobs,pods -n apollo-airlines -l app=init-flight-db
kubectl logs job/init-flight-db -n apollo-airlines
kubectl describe job init-flight-db -n apollo-airlines
```

The Job waits for PostgreSQL with a bounded retry, runs `psql` with
`ON_ERROR_STOP`, and reaches `Complete`. SQL errors are not hidden as success,
and failed Job Pods remain available for `logs` and `describe` evidence.

### 6. Prove application behavior

| Component | URL |
|---|---|
| Frontend | `http://127.0.0.1:30080` |
| Flight | `http://127.0.0.1:30081` |
| Booking | `http://127.0.0.1:30082` |
| Identity | `http://127.0.0.1:30083` |
| Search | `http://127.0.0.1:30084` |

```bash
curl --fail http://127.0.0.1:30080/healthz
curl --fail http://127.0.0.1:30081/api/flights | jq '.flights | length'
curl --fail http://127.0.0.1:30082/readyz
curl --fail http://127.0.0.1:30083/metrics | head
curl --fail http://127.0.0.1:30084/readyz
```

`notification` remains ClusterIP because only Booking calls it. Exposing an
internal-only dependency would add an unnecessary host entry point. Stage 1
exposes NodePorts `30080–30084` as direct local plumbing so you can verify
endpoints right away; Stage 2 Substage 2 teaches the NodePort service model
formally.

## Break 1: delete a controller-owned Pod

Capture the current booking Pods and UIDs:

```bash
kubectl get pods -n apollo-airlines -l app=booking \
  -o custom-columns='NAME:.metadata.name,UID:.metadata.uid,NODE:.spec.nodeName'
BOOKING_POD=$(kubectl get pod -n apollo-airlines -l app=booking \
  -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$BOOKING_POD" -n apollo-airlines
kubectl get pods -n apollo-airlines -l app=booking --watch
```

Stop the watch after two Pods are `Running`. Unlike Ignition's bare Pod, the
deleted name stays gone and the ReplicaSet creates a replacement with a new
UID. Prove the Service recovered behavior:

```bash
kubectl rollout status deployment/booking -n apollo-airlines --timeout=120s
curl --fail http://127.0.0.1:30082/readyz
```

## Break 2: create a failed rolling update

First create one healthy rollout and inspect its new ReplicaSet:

```bash
kubectl rollout restart deployment/search -n apollo-airlines
kubectl rollout status deployment/search -n apollo-airlines --timeout=120s
kubectl get replicasets -n apollo-airlines -l app=search
kubectl rollout history deployment/search -n apollo-airlines
```

Now request an image tag that does not exist:

```bash
kubectl set image deployment/search \
  search=apollo11/search:missing-stage1-demo \
  -n apollo-airlines
kubectl rollout status deployment/search -n apollo-airlines --timeout=30s
```

The rollout status command must time out. That is the symptom, not the cause.
Use the evidence ladder from Ignition:

```bash
kubectl get deployment,replicaset,pod -n apollo-airlines -l app=search
kubectl get events -n apollo-airlines \
  --sort-by=.metadata.creationTimestamp | tail -20
kubectl describe pod -n apollo-airlines \
  -l app=search
kubectl rollout history deployment/search -n apollo-airlines
curl --fail http://127.0.0.1:30084/readyz
```

Look for `ErrImagePull` or `ImagePullBackOff`. The default RollingUpdate
strategy keeps an old healthy replica available, so the Service should still
return 200 even though the new revision cannot complete.

## Recover: roll back the failed revision

```bash
kubectl rollout undo deployment/search -n apollo-airlines
kubectl rollout status deployment/search -n apollo-airlines --timeout=120s
kubectl get replicasets,pods -n apollo-airlines -l app=search
kubectl get deployment search -n apollo-airlines \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl --fail http://127.0.0.1:30084/readyz
```

The working `apollo11/search:latest` image returns, failed Pods disappear, and
the endpoint returns 200. Recovery is complete only after behavior is proven.

> **Note (`kubectl v1.37+` warning):** `kubectl rollout undo` warns that it
> does not update the `kubectl.kubernetes.io/last-applied-configuration`
> annotation on the Deployment. That is expected: the live Deployment spec has
> rolled back, and re-running `kubectl apply` on the Deployment manifest later
> restores client-side apply agreement.

## Automated maintainer verification

The verifier checks the full resource graph, dedicated tokenless identities,
ready endpoints, exact seed data, completed Jobs, health/readiness/metrics, a
reversible booking with request-ID evidence across its logging hops, ReplicaSet Pod
replacement, successful rollout history, failed image diagnosis, rollback, and
post-rollback behavior.

```bash
bash stages/stage1/scripts/verify.sh
```

It deliberately leaves the healthy Stage 1 deployment available for manual
inspection. Run teardown when finished.

## Clean up and audit residue

```bash
bash stages/stage1/scripts/teardown.sh
kubectl get namespace apollo-airlines
kubectl get all -A | grep apollo-airlines || true
```

The namespace query must return `NotFound`, and the residue search must be
empty. The kind cluster is retained for Stage 2.

## Explain

You should now be able to answer:

1. How do a Deployment selector, Pod label, and Service selector connect?
2. What is the ownership chain from Deployment to a running Pod?
3. Why did the ReplicaSet replace a deleted booking Pod while Ignition's Pod
   stayed absent?
4. Why can a Service keep working during a failed rolling update?
5. Which evidence showed that the image—not scheduling or application code—was
   the cause of the failed rollout?
6. What did `rollout undo` change, and how did you prove recovery?
7. When does `emptyDir` data survive, and when is it lost?
8. Why do these workloads have dedicated ServiceAccounts without API tokens?

## What's next

Stage 2 moves from one namespace and direct NodePorts through internal DNS,
Traefik Ingress with local TLS, MetalLB, and finally the Envoy Gateway API
baseline used by later stages.
