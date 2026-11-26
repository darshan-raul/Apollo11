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
2. ClusterIP Services, EndpointSlices, and local verification via `kubectl port-forward`
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
  alternative.
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

### 2. Author before bootstrap (`learner-work/stage1/`)

Before deploying the full fleet, practice authoring the `booking` ConfigMap,
Deployment, and ClusterIP Service in `learner-work/stage1/` (see
[`learner-work/stage1/README.md`](../../learner-work/stage1/README.md)):

```bash
mkdir -p learner-work/stage1/work
cp learner-work/stage1/starter/*.yaml learner-work/stage1/work/
# Edit the manifests in learner-work/stage1/work/, then verify:
bash learner-work/stage1/check.sh
```

### 3. Build and apply

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

### 6. Prove application behavior (`ClusterIP` + `kubectl port-forward`)

Every Service in Stage 1 is strictly `ClusterIP`—there are no host-bound ports
yet. Reach individual Services from your workstation with `kubectl port-forward`
(note `stages/stage1/scripts/build-images.sh` bakes `http://localhost:8080`–`8083`
into the frontend bundle for local port-forwarded access):

| Component | Service | ClusterIP Port | Local `port-forward` command | Local URL |
|---|---|---|---|---|
| Frontend | `frontend` | `3000` | `kubectl port-forward -n apollo-airlines svc/frontend 3000:3000` | `http://127.0.0.1:3000` |
| Identity | `identity` | `8080` | `kubectl port-forward -n apollo-airlines svc/identity 8080:8080` | `http://127.0.0.1:8080` |
| Flight | `flight` | `8081` | `kubectl port-forward -n apollo-airlines svc/flight 8081:8081` | `http://127.0.0.1:8081` |
| Booking | `booking` | `8082` | `kubectl port-forward -n apollo-airlines svc/booking 8082:8082` | `http://127.0.0.1:8082` |
| Search | `search` | `8083` | `kubectl port-forward -n apollo-airlines svc/search 8083:8083` | `http://127.0.0.1:8083` |

Start temporary port-forwards in the background, prove each endpoint, and clean
them up:

```bash
kubectl port-forward -n apollo-airlines svc/frontend 3000:3000 >/tmp/pf-frontend.log 2>&1 &
PF_FE=$!
kubectl port-forward -n apollo-airlines svc/identity 8080:8080 >/tmp/pf-identity.log 2>&1 &
PF_ID=$!
kubectl port-forward -n apollo-airlines svc/flight 8081:8081 >/tmp/pf-flight.log 2>&1 &
PF_FL=$!
kubectl port-forward -n apollo-airlines svc/booking 8082:8082 >/tmp/pf-booking.log 2>&1 &
PF_BK=$!
kubectl port-forward -n apollo-airlines svc/search 8083:8083 >/tmp/pf-search.log 2>&1 &
PF_SR=$!
sleep 2

curl --fail http://127.0.0.1:3000/healthz
curl --fail http://127.0.0.1:8081/api/flights | jq '.flights | length'
curl --fail http://127.0.0.1:8082/readyz
curl --fail http://127.0.0.1:8080/metrics | head
curl --fail http://127.0.0.1:8083/readyz

kill "$PF_FE" "$PF_ID" "$PF_FL" "$PF_BK" "$PF_SR"
```

`notification` (`8084`) is also `ClusterIP` and stays internal because only
Booking calls it. Keeping all Stage 1 Services `ClusterIP` avoids coupling to
host ports early; Stage 2 introduces the full external-exposure progression from
internal DNS through Ingress, MetalLB, and Gateway API.

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
UID. Prove the Service recovered behavior via `kubectl port-forward`:

```bash
kubectl rollout status deployment/booking -n apollo-airlines --timeout=120s
kubectl port-forward -n apollo-airlines svc/booking 8082:8082 >/tmp/pf-booking.log 2>&1 &
PF_BK=$!
sleep 2
curl --fail http://127.0.0.1:8082/readyz
kill "$PF_BK"
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
Use the evidence ladder from Ignition (and record findings with
[`learner-work/EVIDENCE_TEMPLATE.md`](../../learner-work/EVIDENCE_TEMPLATE.md)):

```bash
kubectl get deployment,replicaset,pod -n apollo-airlines -l app=search
kubectl get events -n apollo-airlines \
  --sort-by=.metadata.creationTimestamp | tail -20
kubectl describe pod -n apollo-airlines \
  -l app=search
kubectl rollout history deployment/search -n apollo-airlines
kubectl port-forward -n apollo-airlines svc/search 8083:8083 >/tmp/pf-search.log 2>&1 &
PF_SR=$!
sleep 2
curl --fail http://127.0.0.1:8083/readyz
kill "$PF_SR"
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
kubectl port-forward -n apollo-airlines svc/search 8083:8083 >/tmp/pf-search.log 2>&1 &
PF_SR=$!
sleep 2
curl --fail http://127.0.0.1:8083/readyz
kill "$PF_SR"
```

The working `apollo11/search:latest` image returns, failed Pods disappear, and
the endpoint returns 200. Recovery is complete only after behavior is proven.

> **Note (`kubectl v1.37+` warning):** `kubectl rollout undo` warns that it
> does not update the `kubectl.kubernetes.io/last-applied-configuration`
> annotation on the Deployment. That is expected: the live Deployment spec has
> rolled back, and re-running `kubectl apply` on the Deployment manifest later
> restores client-side apply agreement.

## Break 3: ConfigMap and Secret `env` mutation does not reload running Pods

Kubernetes injects `env` variables (`configMapKeyRef`, `secretKeyRef`, and
`envFrom`) into a container process only when the container starts. Mutating a
ConfigMap or Secret afterward does **not** update environment variables inside
already-running Pods.

Prove this with a short-lived `env-demo` Deployment wired to probe keys on
`apollo-airlines-config` and `apollo-airlines-secrets`:

```bash
kubectl patch configmap apollo-airlines-config -n apollo-airlines --type merge \
  -p '{"data":{"STAGE1_ENV_PROBE":"v1"}}'
kubectl patch secret apollo-airlines-secrets -n apollo-airlines --type merge \
  -p '{"stringData":{"STAGE1_SECRET_PROBE":"s1"}}'

kubectl apply -n apollo-airlines -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: env-demo
  namespace: apollo-airlines
spec:
  replicas: 1
  selector:
    matchLabels:
      app: env-demo
  template:
    metadata:
      labels:
        app: env-demo
    spec:
      serviceAccountName: frontend
      containers:
        - name: env-demo
          image: redis:7-alpine
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "sleep 3600"]
          env:
            - name: DEMO_CFG
              valueFrom:
                configMapKeyRef:
                  name: apollo-airlines-config
                  key: STAGE1_ENV_PROBE
            - name: DEMO_SEC
              valueFrom:
                secretKeyRef:
                  name: apollo-airlines-secrets
                  key: STAGE1_SECRET_PROBE
EOF

kubectl rollout status deployment/env-demo -n apollo-airlines --timeout=120s
ENV_POD=$(kubectl get pod -n apollo-airlines -l app=env-demo \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n apollo-airlines "$ENV_POD" -- printenv DEMO_CFG DEMO_SEC
```

Expected initial output: `v1` and `s1`. Now mutate both objects:

```bash
kubectl patch configmap apollo-airlines-config -n apollo-airlines --type merge \
  -p '{"data":{"STAGE1_ENV_PROBE":"v2"}}'
kubectl patch secret apollo-airlines-secrets -n apollo-airlines --type merge \
  -p '{"stringData":{"STAGE1_SECRET_PROBE":"s2"}}'

kubectl exec -n apollo-airlines "$ENV_POD" -- printenv DEMO_CFG DEMO_SEC
```

The running Pod still prints `v1` and `s1`. Trigger a controlled Pod replacement
with `rollout restart`, then verify the new Pod picks up the updated values:

```bash
kubectl rollout restart deployment/env-demo -n apollo-airlines
kubectl rollout status deployment/env-demo -n apollo-airlines --timeout=120s
NEW_ENV_POD=$(kubectl get pod -n apollo-airlines -l app=env-demo \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n apollo-airlines "$NEW_ENV_POD" -- printenv DEMO_CFG DEMO_SEC
```

The new Pod prints `v2` and `s2`. Clean up the temporary Deployment and restore
the Stage 1 ConfigMap and Secret from their manifests:

```bash
kubectl delete deployment env-demo -n apollo-airlines
kubectl replace -f stages/stage1/k8s/config/configmap.yaml
kubectl replace -f stages/stage1/k8s/config/secrets.yaml
```

> **Preview:** Stage 8 contrasts `env` injection against volume-mounted
> ConfigMaps/Secrets (synced asynchronously by kubelet without Pod restart) and
> automated rollout reloaders for `env`-driven workloads.

## Break 4: Job `backoffLimit` failure proof

Successful Jobs reach `Complete`, whereas failing Jobs retry up to
`spec.backoffLimit` times and then stop with `BackoffLimitExceeded`. With
`restartPolicy: Never`, Kubernetes keeps each failed Pod so you can inspect its
events and logs.

```bash
kubectl apply -n apollo-airlines -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: stage1-backoff-lab
  namespace: apollo-airlines
spec:
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: stage1-backoff-lab
    spec:
      serviceAccountName: init-booking-db
      restartPolicy: Never
      containers:
        - name: fail-probe
          image: postgres:15-alpine
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "echo stage1-backoff-probe >&2; exit 1"]
EOF

kubectl wait --for=condition=Failed job/stage1-backoff-lab -n apollo-airlines --timeout=120s
kubectl get job stage1-backoff-lab -n apollo-airlines
kubectl describe job stage1-backoff-lab -n apollo-airlines
kubectl get pods -n apollo-airlines -l job-name=stage1-backoff-lab
kubectl logs job/stage1-backoff-lab -n apollo-airlines
```

Observe that:
- `status.failed` reaches `3` (`1` initial attempt + `backoffLimit: 2` retries),
- the Job condition reason is `BackoffLimitExceeded`, and
- `kubectl logs job/stage1-backoff-lab` still returns `stage1-backoff-probe`.

Clean up the lab Job:

```bash
kubectl delete job stage1-backoff-lab -n apollo-airlines
```

## Automated maintainer verification

The verifier checks the full resource graph (strictly `ClusterIP` Services with
zero host-port mappings), dedicated tokenless identities, ready endpoints via
`kubectl port-forward`, exact seed data, completed Jobs,
health/readiness/metrics, a reversible booking with request-ID evidence across
its logging hops, ReplicaSet Pod replacement, successful rollout history, failed
image diagnosis and rollback, ConfigMap/Secret `env` mutation non-reload plus
`rollout restart` recovery, and `Job` `backoffLimit` failure proof.

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
9. Why does patching a ConfigMap or Secret not update `env` variables in an
   already-running Pod until a rollout restart occurs?
10. What does `backoffLimit: 2` with `restartPolicy: Never` do when a Job
    keeps failing, and why are the failed Pods retained?

## What's next

Stage 2 moves from one namespace and `ClusterIP` Services accessed via
`kubectl port-forward` through internal DNS, host-port Service exposure,
Traefik Ingress with local TLS, MetalLB, and finally the Envoy Gateway API
baseline used by later stages.
