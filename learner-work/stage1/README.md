# Stage 1 — Author Before Bootstrap (`booking`)

Before running `stages/stage1/scripts/apply.sh` to deploy the full Apollo Airlines fleet, practice authoring the three core Stage 1 primitives for the `booking` service from scratch: a **ConfigMap**, a **Deployment**, and a **ClusterIP Service**.

## Workspace Setup

Copy the starter manifests into `work/` (which is git-ignored) and edit the files inside `work/`:

```bash
mkdir -p learner-work/stage1/work
cp learner-work/stage1/starter/*.yaml learner-work/stage1/work/
```

## Requirements

Complete the three manifests in `learner-work/stage1/work/` so they satisfy the Stage 1 `booking` contract (`stages/stage1/k8s/apps/booking/`):

1. **`booking-cm.yaml` (`ConfigMap`)**:
   - `metadata.name`: `booking-config`
   - `metadata.namespace`: `apollo-airlines`
   - `data`:
     - `PORT`: `"8082"`
     - `FLIGHT_SERVICE_URL`: `"http://flight:8081"`
     - `IDENTITY_SERVICE_URL`: `"http://identity:8080"`
     - `NOTIFICATION_SERVICE_URL`: `"http://notification:8084"`

2. **`booking-dep.yaml` (`Deployment`)**:
   - `metadata.name`: `booking`
   - `metadata.namespace`: `apollo-airlines`
   - `spec.replicas`: `2`
   - `spec.selector.matchLabels` and `spec.template.metadata.labels`: `app: booking`
   - `spec.template.spec.serviceAccountName`: `booking`
   - Container `booking`:
     - `image`: `apollo11/booking:latest`
     - `imagePullPolicy`: `IfNotPresent`
     - `ports`: `containerPort: 8082`
     - `envFrom`: load keys from `configMapRef: { name: booking-config }` (or explicit `env` `configMapKeyRef` entries pointing to `booking-config`)
     - `livenessProbe`: HTTP `GET /healthz` on port `8082`
     - `readinessProbe`: HTTP `GET /readyz` on port `8082`

3. **`booking-svc.yaml` (`Service`)**:
   - `metadata.name`: `booking`
   - `metadata.namespace`: `apollo-airlines`
   - `spec.type`: `ClusterIP` (Stage 1 uses strictly `ClusterIP`)
   - `spec.selector`: `app: booking` (matching the Deployment's Pod template labels)
   - `spec.ports`: `port: 8082`, `targetPort: 8082` (no host port exposure)

> **Fleet note:** When `stages/stage1/scripts/apply.sh` deploys the complete 10-component fleet, `stages/stage1/k8s/apps/booking/booking-dep.yaml` reads shared keys from `apollo-airlines-config` and `apollo-airlines-secrets` so every service shares one central configuration bundle. Here, you wire a dedicated `booking-config` ConfigMap via `envFrom` to isolate and verify the `booking` contract first.

## Validate Your Work

Run the offline verifier against your `work/` directory:

```bash
bash learner-work/stage1/check.sh
```

You can also pass any directory explicitly, or verify the reference solution:

```bash
bash learner-work/stage1/check.sh learner-work/stage1/work
bash learner-work/stage1/check.sh --solution
```

Once `check.sh` passes, return to `stages/stage1/README.md` and run `bash stages/stage1/scripts/apply.sh` to bootstrap the full Stage 1 fleet.
