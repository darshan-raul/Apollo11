---
title: "Stage 4: Flight Control — Reliability, Lifecycle, Governance, and Placement"
description: "Startup/liveness/readiness probes, Guaranteed QoS, lifecycle preStop hooks, PriorityClasses, tolerations, nodeAffinity, topologySpreadConstraints, LimitRange, ResourceQuota, and PodDisruptionBudgets. Built on Stage 3 StatefulSets and the Envoy Gateway + MetalLB access stack."
---

# Stage 4: Flight Control

**Goal:** Transform the running workloads into a production-grade, reliable, and well-governed fleet. The kubelet must know when a container is still bootstrapping (`startupProbe`), when to restart a hung process (`livenessProbe`), and when to pull a pod from Service traffic (`readinessProbe`). The runtime must avoid dropped requests during rolling updates via **graceful SIGTERM drains and `preStop` hooks**. The scheduler and namespaces enforce **resource governance** (`LimitRange`, `ResourceQuota`, and `requests == limits` Guaranteed QoS), **scheduling priorities and placement** (`PriorityClass`, `tolerations`, `nodeAffinity`, and `topologySpreadConstraints`), and **voluntary disruption protection** (`PodDisruptionBudget`).

| | |
|---|---|
| **Curriculum Sequence** | Probes → Drains & Lifecycle Hooks → QoS, `LimitRange` & `ResourceQuota` → Priority, Taints/Tolerations, `nodeAffinity` & Topology Spread → PodDisruptionBudgets |
| **New Concepts** | `startupProbe`, `livenessProbe`, `readinessProbe`, `preStop` lifecycle hook, `terminationGracePeriodSeconds`, Guaranteed QoS, `LimitRange`, `ResourceQuota`, `PriorityClass`, `tolerations`, `nodeAffinity`, `topologySpreadConstraints` (`nodeTaintsPolicy: Honor`), `PodDisruptionBudget`, Eviction API |
| **Workloads Changed** | 10 (6 app Deployments + 4 StatefulSets) |
| **Verify Target** | Automated lifecycle, governance, scheduling, probe/cgroup, and zero-drop rolling-restart proofs |

---

## Author Before Bootstrap (`learner-work/stage4/`)

Before running `./stages/stage4/scripts/apply.sh`, practice upgrading the Stage 3 `booking` Deployment yourself in [`learner-work/stage4/`](../../learner-work/stage4/README.md):

```bash
cp -r learner-work/stage4/starter learner-work/stage4/work
# Edit learner-work/stage4/work/booking-dep.yaml and add booking-pdb.yaml
bash learner-work/stage4/check.sh
```

Use `bash learner-work/stage4/check.sh --solution` to check the reference solution.

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

4. **Scheduling Ownership (`PriorityClass`, `tolerations`, `nodeAffinity`, `topologySpreadConstraints`):**
   - Two cluster-scoped `PriorityClass` resources govern scheduling importance:
     - `apollo-airlines-app-critical` (`value: 1000000`): Assigned to flagship `booking` and `search`.
     - `apollo-airlines-app-low` (`value: -100000`): Assigned to background `notification`.
   - `search` demonstrates full placement policy:
     - `tolerations`: tolerates `workload=search:NoSchedule` so dedicated search nodes can be tainted without blocking `search`.
     - `affinity.nodeAffinity`: `preferredDuringSchedulingIgnoredDuringExecution` (`weight: 100`) preferring `apollo11.io/search-pool: dedicated`.
     - `topologySpreadConstraints`: `maxSkew: 1` on `kubernetes.io/hostname` with `whenUnsatisfiable: DoNotSchedule` and `nodeTaintsPolicy: Honor` (so tainted/unschedulable nodes do not skew spread math).
   - `booking`, `flight`, `identity`, `notification`, and `frontend` declare `topologySpreadConstraints` with `maxSkew: 1` on `kubernetes.io/hostname` (`whenUnsatisfiable: ScheduleAnyway`) to distribute replicas across worker nodes.

5. **Namespace Governance (`LimitRange` & `ResourceQuota`):**
   - `LimitRange` (`apollo-airlines-limits` in `apollo-airlines-apps`, `apollo-ui-limits` in `apollo-airlines-ui`): enforces container `min` (`10m` CPU / `16Mi` memory) and `max` (`2` CPU / `2Gi` in apps; `1` CPU / `1Gi` in UI) bounds and injects `defaultRequest` (`50m` / `64Mi`) and `default` (`100m` / `128Mi`) for containers (such as one-off `seed-*` Jobs) that omit explicit resources.
   - `ResourceQuota` (`apollo-airlines-quota` in `apollo-airlines-apps`: `30` pods, `4` CPU, `4Gi` memory; `apollo-ui-quota` in `apollo-airlines-ui`: `10` pods, `1` CPU, `1Gi` memory): caps total namespace consumption while leaving headroom for rolling updates and temporary lab Pods.

6. **PodDisruptionBudgets (PDB):**
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

# Inspect PriorityClasses, search placement policies, LimitRanges, and ResourceQuotas
kubectl get priorityclass
kubectl get deployment booking -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.priorityClassName}{'\n'}"
# Output: apollo-airlines-app-critical

kubectl get deployment search -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.tolerations}{'\n'}{.spec.template.spec.affinity}{'\n'}{.spec.template.spec.topologySpreadConstraints}{'\n'}"

kubectl describe limitrange -n apollo-airlines-apps
kubectl describe resourcequota -n apollo-airlines-apps
kubectl describe resourcequota -n apollo-airlines-ui

# Inspect replica distribution across nodes (non-control-plane workers)
kubectl get pods -n apollo-airlines-apps -l app=booking -o wide
# Look at the NODE column: replicas should be spread across available worker nodes
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
sleep 10
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true
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

#### Experiment 3: Reversible Node Taint & Scheduling Gate
Discover the first worker node dynamically, apply a `NoSchedule` taint, confirm an untolerated pod pinned to that node remains `Unschedulable`, then remove the taint and delete the probe pod:
```bash
TARGET_NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath="{.items[0].metadata.name}")
kubectl taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: taint-probe
  namespace: apollo-airlines-apps
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  nodeSelector:
    kubernetes.io/hostname: ${TARGET_NODE}
  containers:
    - name: pause
      image: busybox:1.36
      command: ["sh", "-c", "sleep 5"]
      resources:
        requests: { cpu: 10m, memory: 16Mi }
        limits: { cpu: 10m, memory: 16Mi }
EOF
kubectl describe pod taint-probe -n apollo-airlines-apps | tail -n 10
# Expected: Pending / Unschedulable because node(s) had untolerated taint apollo11.io/maintenance

kubectl delete pod taint-probe -n apollo-airlines-apps
kubectl taint node "$TARGET_NODE" apollo11.io/maintenance=true:NoSchedule-
```

#### Experiment 4: Readiness vs. Liveness Failure (`EndpointSlice` Removal vs. Container Restart)
Prove that failing `readinessProbe` removes the Pod IP from its Service `EndpointSlice` with `0` container restarts, whereas failing `livenessProbe` causes kubelet to kill and restart the container:
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: stage4-probe-lab
  namespace: apollo-airlines-apps
spec:
  selector:
    app: stage4-probe-lab
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: stage4-probe-lab
  namespace: apollo-airlines-apps
  labels:
    app: stage4-probe-lab
spec:
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: probe
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command:
        - python3
        - -c
        - |
          import http.server, os, socketserver
          open("/tmp/ready", "w").close(); open("/tmp/live", "w").close()
          class H(http.server.BaseHTTPRequestHandler):
              def do_GET(self):
                  ok = os.path.exists("/tmp/ready" if self.path == "/ready" else "/tmp/live")
                  self.send_response(200 if ok else 503)
                  self.end_headers()
              def log_message(self, *a): pass
          socketserver.TCPServer.allow_reuse_address = True
          with socketserver.TCPServer(("", 8080), H) as s: s.serve_forever()
      readinessProbe:
        httpGet: { path: /ready, port: 8080 }
        periodSeconds: 2
        failureThreshold: 1
      livenessProbe:
        httpGet: { path: /live, port: 8080 }
        periodSeconds: 2
        failureThreshold: 2
      resources:
        requests: { cpu: 20m, memory: 32Mi }
        limits: { cpu: 20m, memory: 32Mi }
EOF
kubectl wait --for=condition=Ready pod/stage4-probe-lab -n apollo-airlines-apps --timeout=45s

# 1) Fail readiness: EndpointSlice ready address disappears, restartCount stays 0
kubectl exec -n apollo-airlines-apps stage4-probe-lab -- rm -f /tmp/ready
sleep 5
kubectl get endpointslices -n apollo-airlines-apps -l kubernetes.io/service-name=stage4-probe-lab -o yaml
kubectl get pod stage4-probe-lab -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'

# 2) Fail liveness: kubelet kills and restarts the container (restartCount >= 1)
kubectl exec -n apollo-airlines-apps stage4-probe-lab -- rm -f /tmp/live
sleep 8
kubectl get pod stage4-probe-lab -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'

kubectl delete pod stage4-probe-lab -n apollo-airlines-apps
kubectl delete service stage4-probe-lab -n apollo-airlines-apps
```

#### Experiment 5: OOMKill (`ExitCode 137`) & CPU Throttling (`cpu.stat`)
Prove kernel cgroup enforcement on both memory (`OOMKilled`, `ExitCode 137`) and CPU (`nr_throttled` / `throttled_usec` in `/sys/fs/cgroup/cpu.stat`):
```bash
# Memory limit enforcement -> OOMKilled (ExitCode 137)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stage4-oom-probe
  namespace: apollo-airlines-apps
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: oom
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command: ["python3", "-c", "a = bytearray(64 * 1024 * 1024)"]
      resources:
        requests: { cpu: 20m, memory: 16Mi }
        limits: { cpu: 20m, memory: 16Mi }
EOF
sleep 6
kubectl get pod stage4-oom-probe -n apollo-airlines-apps -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
# Expected: OOMKilled 137
kubectl delete pod stage4-oom-probe -n apollo-airlines-apps

# CPU quota enforcement -> throttling counters in cgroup cpu.stat
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stage4-cpu-probe
  namespace: apollo-airlines-apps
spec:
  restartPolicy: Never
  priorityClassName: apollo-airlines-app-low
  containers:
    - name: burn
      image: apollo11/identity:latest
      imagePullPolicy: IfNotPresent
      command:
        - python3
        - -c
        - "import time; end=time.time()+3.0; x=0\nwhile time.time()<end: x+=1\nprint(open('/sys/fs/cgroup/cpu.stat').read())"
      resources:
        requests: { cpu: 10m, memory: 32Mi }
        limits: { cpu: 10m, memory: 32Mi }
EOF
sleep 8
kubectl logs -n apollo-airlines-apps stage4-cpu-probe
# Expected: nr_throttled > 0 and throttled_usec > 0
kubectl delete pod stage4-cpu-probe -n apollo-airlines-apps
```

#### Experiment 6: Zero-Drop In-Flight Traffic During `preStop` Rolling Restart
Send continuous HTTP requests to `booking` through Envoy Gateway while rolling `deployment/booking` and verify `0` failed requests:
```bash
GATEWAY_IP=$(kubectl -n envoy-gateway-system get service -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
STOP=$(mktemp -u); LOG=$(mktemp)
(while [[ ! -f "$STOP" ]]; do curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 -H "Host: booking.apollo.local" "http://${GATEWAY_IP}/healthz" >> "$LOG"; sleep 0.1; done) &
LOAD_PID=$!
kubectl rollout restart deployment/booking -n apollo-airlines-apps
kubectl rollout status deployment/booking -n apollo-airlines-apps --timeout=120s
touch "$STOP"; wait "$LOAD_PID" 2>/dev/null || true
echo "Total: $(wc -l < "$LOG"), Non-200: $(awk '$1 != "200" {c++} END {print c+0}' "$LOG")"
rm -f "$STOP" "$LOG"
```

---

### 3b. Blind Troubleshooting Drill (`fault-drill.sh`)

Test your Stage 4 debugging instincts without looking at the injected fault:

```bash
./stages/stage4/scripts/fault-drill.sh --inject
```

Diagnose using only the Ignition 5-rung evidence ladder (`Status -> Events -> Detail -> Logs -> Behavior`), document your evidence in `learner-work/stage4/work/fault-drill.md` using [`learner-work/EVIDENCE_TEMPLATE.md`](../../learner-work/EVIDENCE_TEMPLATE.md), apply the fix, and validate recovery:

```bash
./stages/stage4/scripts/fault-drill.sh --verify
# Or restore clean Stage 4 manifests at any time:
./stages/stage4/scripts/fault-drill.sh --restore
```

---

### 4. Recover: Restoring Cluster Balance

Verify that during the disruption experiment, live traffic through Envoy Gateway continued uninterrupted:
```bash
GATEWAY_IP=$(kubectl -n envoy-gateway-system get service -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl -fsS -H "Host: booking.apollo.local" "http://${GATEWAY_IP}/healthz"
```

Wait for the replacement pod to initialize and confirm PDB recovery:
```bash
kubectl rollout status deployment/booking -n apollo-airlines-apps
kubectl get pdb booking-pdb -n apollo-airlines-apps
# currentHealthy returns to 2, allowed disruptions returns to 1.
```

---

## Explain

1. **What is the operational difference between `livenessProbe` and `readinessProbe`?**
   A liveness failure kills and restarts the container via kubelet (`restartCount` increments). A readiness failure merely removes the pod IP from `EndpointSlice` ready addresses (stopping traffic) while keeping the process alive to recover (`0` restarts).
2. **Why is a `preStop` hook needed if the app already handles SIGTERM gracefully?**
   Kubernetes endpoint deregistration (kube-proxy / Envoy) happens asynchronously in parallel with `SIGTERM`. The `sleep 5` `preStop` hook gives data-plane routing tables time to drain the endpoint before the application listener starts closing.
3. **What makes a pod `Guaranteed` QoS vs `Burstable`, and what triggers `OOMKilled` (`ExitCode 137`) vs CPU throttling?**
   `Guaranteed` requires `requests == limits` for both CPU and memory on all containers; `Burstable` has lower requests than limits or omits limits. Memory is non-compressible: exceeding `limits.memory` triggers a kernel cgroup OOMKill (`SIGKILL`, exit `137`), whereas CPU is compressible: exceeding `limits.cpu` throttles execution across CFS periods (`nr_throttled` / `throttled_usec` in `cpu.stat`) without killing the process.
4. **How do `PriorityClass`, `tolerations`, `nodeAffinity`, and `topologySpreadConstraints` work together?**
   `PriorityClass` ranks pod scheduling and preemption importance (`apollo-airlines-app-critical` vs `apollo-airlines-app-low`); `tolerations` allow pods such as `search` to land on matching tainted nodes; `nodeAffinity` expresses preferred or required node labels (`apollo11.io/search-pool=dedicated`); and `topologySpreadConstraints` (`nodeTaintsPolicy: Honor`) balances replicas across nodes without counting untolerated tainted nodes against skew.
5. **How do `LimitRange` and `ResourceQuota` protect shared namespaces?**
   `LimitRange` sets per-container min/max bounds and default requests/limits on admission, while `ResourceQuota` caps aggregate pod count, CPU, and memory across the namespace.
6. **How does `PodDisruptionBudget` protect availability during voluntary disruptions?**
   `PodDisruptionBudget` (`minAvailable: 1`) gates the Eviction API so node drains or voluntary evictions cannot reduce healthy replicas below the configured threshold.

---

## File Layout

```
stages/stage4/
├── README.md
├── code/                              # Snapshot of Stage 3 code + probe endpoints & SIGTERM drains
├── scripts/
│   ├── apply.sh                       # 8-step idempotent orchestrator
│   ├── verify.sh                      # Automated checks (governance, scheduling, probe/cgroup & zero-drop proofs)
│   ├── verify-tls.sh                  # Trusted HTTPS workflow & hostname rejection check
│   ├── fault-drill.sh                 # Randomized Blind Troubleshooting break-fix drill
│   ├── generate-certs.sh              # Self-signed wildcard TLS cert generator
│   ├── teardown.sh                    # Teardown with zero cluster residue
│   └── build-images.sh                # Builds & loads all 6 application images
└── k8s/
    ├── config/                        # Namespaces, ConfigMap, Secret, 13 SAs, PriorityClasses, LimitRange, ResourceQuota
    ├── apps/
    │   ├── identity-db/, flight-db/, booking-db/, redis/   # StatefulSets (Guaranteed QoS, 60s grace)
    │   ├── identity/, flight/, booking/, search/, notification/, frontend/ # Deployments (probes, QoS, preStop, scheduling)
    ├── jobs/                          # Seed ConfigMaps (*-db-seed.yaml) & Jobs (seed-*-db.yaml)
    ├── pdb/                           # booking-pdb, frontend-pdb (minAvailable: 1)
    ├── gateway/                       # Envoy Gateway v1.5.0 + EnvoyProxy + HTTPRoutes
    └── metallb/                       # MetalLB L2 IP pool & advertisement
```

Also see [`learner-work/stage4/`](../../learner-work/stage4/README.md) for the pre-bootstrap `booking` reliability & PDB exercise.

---

## Verification

Run the verification suite:
```bash
./stages/stage4/scripts/verify.sh
```

## Shared Local HTTPS & Image Guides

Stage 4 uses local-built `apollo11/<service>:latest` images with HTTPS `VITE_*` URLs and stores the Envoy Gateway wildcard TLS Secret as `apollo-tls-secret` in `apollo-airlines-apps`. Export `KUBE_CONTEXT=kind-apollo11` (or `kind-apollo11-dev`) before running Stage 4 scripts.

- **Local HTTPS, TLS Secret ownership, `mkcert`, `/etc/hosts`, and TLS break/recover:** see [Local HTTPS, TLS Certificates & Gateway Routing](../../docs/local-https.md).
- **Local `build-images.sh` + `kind load` and stage-switch rebuild rules:** see [CI Pipeline, Published GHCR Images & Local Image Contract](../../docs/ci-images.md).
