# Stage 4 — Author Before Bootstrap: Booking Reliability & PDB

Before running `./stages/stage4/scripts/apply.sh`, practice upgrading the Stage 3 `booking` Deployment (`starter/booking-dep.yaml`) to Stage 4 reliability and disruption-budget standards.

## Objectives

Copy `starter/` to `work/` and edit the manifests in `work/`:

```bash
cp -r learner-work/stage4/starter learner-work/stage4/work
```

Update `work/booking-dep.yaml` and create `work/booking-pdb.yaml` to satisfy all of the following Stage 4 contracts:

1. **Three Distinct Probe Paths** on container `booking` (port `8082`):
   - `startupProbe`: HTTP `GET /healthz/startup` on port `8082` (`initialDelaySeconds: 0`, `periodSeconds: 5`, `failureThreshold: 6`)
   - `livenessProbe`: HTTP `GET /healthz/live` on port `8082` (`initialDelaySeconds: 15`, `periodSeconds: 10`, `failureThreshold: 3`)
   - `readinessProbe`: HTTP `GET /healthz/ready` on port `8082` (`initialDelaySeconds: 5`, `periodSeconds: 5`, `failureThreshold: 3`)
2. **Guaranteed QoS (`requests == limits`)** on every container (including `initContainers` if retained):
   - Set equal CPU and memory `requests` and `limits` on `booking` (e.g., `cpu: 200m`, `memory: 256Mi`).
3. **Graceful Drain (`lifecycle.preStop` + `terminationGracePeriodSeconds`)**:
   - Add `lifecycle.preStop.exec.command` (e.g., `["/bin/sh", "-c", "sleep 5"]`) so kube-proxy and Envoy deregister the Pod endpoint before `SIGTERM` closes the listener.
   - Set `spec.template.spec.terminationGracePeriodSeconds: 30`.
4. **PodDisruptionBudget (`work/booking-pdb.yaml`)**:
   - `apiVersion: policy/v1`, `kind: PodDisruptionBudget`, `metadata.name: booking-pdb`, `metadata.namespace: apollo-airlines-apps`.
   - Set `spec.minAvailable: 1` (or `maxUnavailable`) and `spec.selector.matchLabels` matching `app: booking`.

## Validate Your Work

```bash
# Validate learner-work/stage4/work/ (default)
bash learner-work/stage4/check.sh

# Validate an explicit directory
bash learner-work/stage4/check.sh learner-work/stage4/starter   # expected to fail

# Validate the reference solution
bash learner-work/stage4/check.sh --solution
```
