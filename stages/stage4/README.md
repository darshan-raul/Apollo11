---
title: "Stage 4: Flight Control — Reliability, Lifecycle, Governance, and Placement"
description: "Startup/liveness/readiness probes, Guaranteed QoS resource governance, lifecycle preStop hooks, PriorityClasses, topology spread constraints, and PodDisruptionBudgets. Built on Stage 3 StatefulSets and the Envoy Gateway + MetalLB access stack."
---

> **Current verification status:** the context, TLS, and contract fixes in this
> working tree require a fresh runtime lifecycle. Counts below record earlier
> revisions; use the current verifier's summary rather than expecting those totals.

# Stage 4: Flight Control

**Goal:** Transform the running workloads into a production-grade, reliable, and well-governed fleet. The kubelet must know when a container is still bootstrapping (`startupProbe`), when to restart a hung process (`livenessProbe`), and when to pull a pod from Service traffic (`readinessProbe`). The runtime must avoid dropped requests during rolling updates via **graceful SIGTERM drains and `preStop` hooks**. The scheduler needs **resource budgets** (`requests == limits` defining Guaranteed QoS), **scheduling priorities** (`PriorityClass`), and **multi-node replica distribution** (`topologySpreadConstraints`). Finally, voluntary disruptions (evictions, upgrades) are governed by **`PodDisruptionBudget`** to ensure zero user-facing downtime.

| | |
|---|---|
| **Curriculum Sequence** | Probes → Drains & Lifecycle Hooks → Guaranteed QoS → Priority & Topology Spread → PodDisruptionBudgets |
| **New Concepts** | `startupProbe`, `livenessProbe`, `readinessProbe`, `preStop` lifecycle hook, `terminationGracePeriodSeconds`, `resources.{requests,limits}`, Guaranteed QoS, `PriorityClass`, `topologySpreadConstraints`, `PodDisruptionBudget`, Eviction API |
| **Workloads Changed** | 10 (6 app Deployments + 4 StatefulSets) |
| **Verify Target** | **148/148 checks pass** |

---

## The Learner-First Lab Contract

### 1. Build: The Reliability & Governance Stack

Stage 4 enhances our 10 workloads across 5 core dimensions:

1. **Three Distinct Probe Paths:**
   - `/healthz/startup`: Kubelet startup check. Grants a 30s window (6 × 5s) for slow container bootstrap before liveness checks start.
   - `/healthz/live`: Kubelet liveness check. Confirms process vitality. Failure triggers a container restart.
   - `/healthz/ready`: Kubelet readiness check. Validates downstream database/Redis reachability. Failure removes the pod IP from Service endpoints without restarting the process.
   - *StatefulSets:* Kept on `pg_isready` / `redis-cli ping` exec probes; no `startupProbe` is added because database initialization (`initdb`) blocks connections until completion.

2. **Graceful SIGTERM Drain & `preStop` Lifecycle Hooks:**
   - Go services (`srv.Shutdown(ctx)` with a 30s timeout) and Python identity (`uvicorn` with `timeout_graceful_shutdown=30`) drain in-flight requests on SIGTERM.
   - Deployments configure a `preStop` hook (`sleep 5`):
     ```yaml
     lifecycle:
       preStop:
         exec:
           command: ["/bin/sh", "-c", "sleep 5"]
     ```
     *Why this matters:* When a pod terminates, Kubernetes asynchronously removes its IP from Service endpoints and kube-proxy / Envoy routing tables while sending SIGTERM to the container. The `preStop` hook gives routing tables time to de-register the pod before the application listener starts refusing connections.

3. **Guaranteed Quality of Service (QoS):**
   - Every container sets `requests == limits` for both CPU and memory.
   - Kubernetes assigns `qosClass: Guaranteed`, granting pods the highest eviction resistance under node resource exhaustion.

   | Tier | Workloads | CPU (req/lim) | Memory (req/lim) |
   |---|---|---|---|
   | App Default | `identity`, `flight`, `search` | 100m | 128Mi |
   | Flagship | `booking` | 200m | 256Mi |
   | Low Traffic | `notification` | 50m | 64Mi |
   | UI / NGINX | `frontend` | 50m | 64Mi |
   | Postgres | `identity-db`, `flight-db`, `booking-db` | 200m | 256Mi |
   | Redis | `redis` | 100m | 128Mi |

4. **PriorityClasses & Topology Spread Constraints:**
   - Two cluster-scoped `PriorityClass` resources govern scheduling importance:
     - `apollo-airlines-app-critical` (`value: 1000000`): Assigned to flagship `booking` and `search`.
     - `apollo-airlines-app-low` (`value: -100000`): Assigned to background `notification`.
   - App Deployments declare `topologySpreadConstraints` with `maxSkew: 1` on `kubernetes.io/hostname`, ensuring replicas are evenly distributed across kind worker nodes (`apollo11-worker` and `apollo11-worker2`).

5. **PodDisruptionBudgets (PDB):**
   - `booking-pdb` in `apollo-airlines-apps` (`minAvailable: 1`)
   - `frontend-pdb` in `apollo-airlines-ui` (`minAvailable: 1`)
   - Ensures voluntary evictions cannot take down all healthy replicas simultaneously.

---

### 2. Inspect: Observing Reliability in the Cluster

Run the deployment script:
```bash
./stages/stage4/scripts/apply.sh
```

Inspect probes and QoS:
```bash
# Check probe configuration on booking
kubectl describe deployment booking -n apollo-airlines-apps | grep -E "(Liveness|Readiness|Startup)"

# Verify QoS class is Guaranteed
kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath="{.items[*].status.qosClass}"
# Output: Guaranteed Guaranteed

# Inspect PriorityClasses
kubectl get priorityclass
kubectl get deployment booking -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.priorityClassName}"
# Output: apollo-airlines-app-critical

# Inspect replica distribution across nodes
kubectl get pods -n apollo-airlines-apps -l app=booking -o wide
# Look at the NODE column: replicas should be spread across apollo11-worker and apollo11-worker2
```

Inspect PDB health:
```bash
kubectl get pdb -A
# NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# booking-pdb    1               N/A               1                     ...
# frontend-pdb   1               N/A               1                     ...
```

---

### 3. Break: Failure Experiments

#### Experiment 1: Graceful SIGTERM Shutdown & Drain
Terminate a running booking pod while following logs to observe the shutdown lifecycle:
```bash
POD=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath="{.items[0].metadata.name}")
kubectl logs -n apollo-airlines-apps "$POD" -f &
LOG_PID=$!
sleep 1
kubectl delete pod -n apollo-airlines-apps "$POD" --wait=false
```
**Expected Observation:** The log outputs:
`{"level":"INFO","message":"Received SIGTERM, shutting down gracefully"}`
The process executes `srv.Shutdown()` and closes the database connection cleanly before the container exits.

#### Experiment 2: PodDisruptionBudget Exhaustion
Test Kubernetes Eviction API directly against the `booking` service:
```bash
POD1=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath="{.items[0].metadata.name}")
POD2=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath="{.items[1].metadata.name}")

# Evict first pod (allowed because 2 healthy pods exist and minAvailable=1)
kubectl create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD1}/eviction" -f - <<EOF
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"${POD1}","namespace":"apollo-airlines-apps"}}
EOF
# Returns: {"status":"Success","code":201}

# Immediately attempt to evict the second pod while the budget is 0
kubectl create --raw "/api/v1/namespaces/apollo-airlines-apps/pods/${POD2}/eviction" -f - <<EOF
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"${POD2}","namespace":"apollo-airlines-apps"}}
EOF
```
**Expected Observation:** The API server rejects the second eviction:
`Error from server (TooManyRequests): Cannot evict pod as it would violate the pod disruption budget.`

---

### 4. Recover: Restoring Cluster Balance

Verify that during the disruption experiment, live traffic through Envoy Gateway continued uninterrupted:
```bash
curl -i -H "Host: booking.apollo.local" http://172.18.0.50/healthz
# HTTP/1.1 200 OK
```

Wait for the replacement pod to initialize and confirm PDB recovery:
```bash
kubectl rollout status deployment/booking -n apollo-airlines-apps
kubectl get pdb booking-pdb -n apollo-airlines-apps
# currentHealthy returns to 2, allowed disruptions returns to 1.
```

---

### 5. Explain: Concepts You Should Master

1. **What is the operational difference between `livenessProbe` and `readinessProbe`?**
   A liveness failure kills and restarts the container via kubelet. A readiness failure merely removes the pod IP from Service endpoints (preventing traffic) while leaving the process running to recover.
2. **Why is a `preStop` hook needed if the app already handles SIGTERM gracefully?**
   Kubernetes endpoint deregistration (kube-proxy / Envoy) happens in parallel with SIGTERM. The `sleep 5` preStop hook guarantees new requests stop routing to the pod before the application listener starts closing.
3. **What makes a pod `Guaranteed` QoS vs `Burstable`?**
   `Guaranteed` requires `requests == limits` for both CPU and memory on all containers. `Burstable` has requests lower than limits or limits omitted.
4. **Why do we assign `apollo-airlines-app-critical` to booking and search?**
   Under node resource starvation, Kubernetes scheduler evicts pods with lower priority (such as `notification`) to keep revenue-generating booking services alive.
5. **How does `topologySpreadConstraints` improve availability in a multi-node cluster?**
   It prevents the scheduler from placing all replicas of a service on the same node, ensuring node failure or drain leaves surviving replicas on other nodes.

---

## File Layout

```
stages/stage4/
├── README.md
├── code/                              # Snapshot of Stage 3 code + probe endpoints & SIGTERM drains
├── scripts/
│   ├── apply.sh                       # 8-step idempotent orchestrator
│   ├── verify.sh                      # 148 automated checks including eviction & placement proofs
│   ├── teardown.sh                    # Teardown with zero cluster residue
│   └── build-images.sh                # Builds & loads all 6 application images
└── k8s/
    ├── config/                        # Namespaces, ConfigMap, Secret, 13 SAs, PriorityClasses
    ├── apps/
    │   ├── identity-db/, flight-db/, booking-db/, redis/   # StatefulSets (Guaranteed QoS, 60s grace)
    │   ├── identity/, flight/, booking/, search/, notification/, frontend/ # Deployments (probes, QoS, preStop, topologySpread)
    ├── jobs/                          # Idempotent seed jobs
    ├── pdb/                           # booking-pdb, frontend-pdb (minAvailable: 1)
    ├── gateway/                       # Envoy Gateway v1.5.0 + EnvoyProxy + HTTPRoutes
    └── metallb/                       # MetalLB L2 IP pool & advertisement
```

---

## Verification

Run the verification suite:
```bash
./stages/stage4/scripts/verify.sh
```

**Expected Result: 148/148 checks pass.**

## Local HTTPS and certificate ownership

The canonical Gateway offers HTTP on port 80 and HTTPS on port 443. Frontend
API URLs are now baked as HTTPS; rebuild images before switching snapshots.
The certificate Secret is generated at installation time and preserved across
reapplication. It is not part of Helm release ownership or the Kustomize base.
Use `bash scripts/generate-certs.sh --rotate` to renew it deliberately.

Export `KUBE_CONTEXT=kind-apollo11` (or `kind-apollo11-dev`) before using the
scripts. For a manual Helm/Kustomize install, create both application namespaces
and run the certificate generator before submitting Gateway resources. Argo CD
bootstrap prepares separate certificates in each tenant's namespaces.

Extract the public certificate, then check the actual DNS hostname and trust:

```bash
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get secret apollo-tls-secret \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/apollo-ca.crt
gateway_ip=$(kubectl --context "$KUBE_CONTEXT" -n envoy-gateway-system get service \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl --cacert /tmp/apollo-ca.crt --resolve "identity.apollo.local:443:$gateway_ip" \
  https://identity.apollo.local/healthz
```

Add the Gateway address and all five hostnames to local name resolution before
using the browser. Trust the local certificate using your browser/OS's local
certificate facility, then open `https://frontend.apollo.local`. Verify login,
flight search, and a reversible booking in the browser's Network panel: all API
requests must use HTTPS. A successful HTML response alone does not establish
that behavior. `curl -k` skips trust verification and is only a diagnostic.

Delete the apps-namespace certificate to break the HTTPS listener. HTTP should
remain available. Re-run the certificate generator and require a trusted HTTPS
response plus login/search recovery. If the old certificate was deleted,
extract the replacement and update local trust. Teardown removes the runtime
certificate when it deletes the owned namespace.
