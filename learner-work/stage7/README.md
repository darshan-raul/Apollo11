# Stage 7 — Author Before Bootstrap: Search HorizontalPodAutoscaler

Before running `./stages/stage7/scripts/apply.sh`, author the `autoscaling/v2` `HorizontalPodAutoscaler` for `search` (`starter/search-hpa.yaml`) and verify its spec offline before observing live metrics and target scaling on the cluster.

## Objectives

Copy `starter/` to `work/` and edit `work/search-hpa.yaml`:

```bash
mkdir -p learner-work/stage7/work
cp learner-work/stage7/starter/*.yaml learner-work/stage7/work/
```

Update `work/search-hpa.yaml` to satisfy all of the following Stage 7 HPA contracts:

1. **API Version & Metadata**:
   - `apiVersion: autoscaling/v2`
   - `kind: HorizontalPodAutoscaler`
   - `metadata.name: search-hpa`
   - `metadata.namespace: apollo-airlines-apps`
2. **Scale Target (`spec.scaleTargetRef`)**:
   - `apiVersion: apps/v1`
   - `kind: Deployment`
   - `name: search`
3. **Replica Bounds & CPU Target**:
   - `minReplicas: 2` (chart default; `1..3` accepted by `check.sh`, `values-dev.yaml` overrides to `1`)
   - `maxReplicas: 10` (`>= 3` and strictly greater than `minReplicas`)
   - `spec.metrics`: a `Resource` metric for `cpu` with `target.type: Utilization` and `target.averageUtilization: 70` (measured against `search`'s `100m` CPU request).
4. **Asymmetric Scaling Behavior (`spec.behavior`)**:
   - `scaleDown.stabilizationWindowSeconds: 300` (5-minute cooldown to avoid flapping, plus a controlled `Percent` policy such as `50` per `60`s).
   - `scaleUp.stabilizationWindowSeconds: 0` with non-empty `scaleUp.policies` (e.g., `Percent: 100` and `Pods: 4` per `30`s, `selectPolicy: Max`) to react quickly to traffic spikes.

## Validate Offline

```bash
# Validate learner-work/stage7/work/ (default)
bash learner-work/stage7/check.sh

# Validate starter/ (expected to fail)
bash learner-work/stage7/check.sh learner-work/stage7/starter

# Validate the reference solution
bash learner-work/stage7/check.sh --solution
```

Compare your manifest against the Stage 7 Helm chart's HPA template:

```bash
helm template apollo11 stages/stage7/helm/apollo11 \
  -s templates/autoscaling/search-hpa.yaml | diff -u - learner-work/stage7/work/search-hpa.yaml || true
```

## Validate Live Cluster Metrics & Target Scaling

After bootstrapping Stage 7 (`bash stages/stage7/scripts/apply.sh --env dev`):

```bash
export KUBE_CONTEXT="${KUBE_CONTEXT:-kind-apollo11}"

# 1. Confirm metrics-server (metrics.k8s.io) is serving node and pod metrics
kubectl --context "$KUBE_CONTEXT" top nodes
kubectl --context "$KUBE_CONTEXT" top pods -n apollo-airlines-apps

# 2. Confirm search-hpa reads live CPU utilization (TARGETS must show <pct>%/70%, not <unknown>)
kubectl --context "$KUBE_CONTEXT" get hpa search-hpa -n apollo-airlines-apps
kubectl --context "$KUBE_CONTEXT" describe hpa search-hpa -n apollo-airlines-apps

# 3. Drive load and observe HPA scale-out and scale-in
bash stages/stage7/scripts/scaling-lab.sh --context "$KUBE_CONTEXT"
# Or run the capacity profile against the Gateway (see stages/stage7/PERFORMANCE.md):
# SSL_CERT_FILE=/tmp/apollo-edge.crt BASE_URL=https://search.apollo.local k6 run stages/stage7/k6/capacity.js
```

Document any discrepancy or failure investigation using [the learner evidence template](../EVIDENCE_TEMPLATE.md).
