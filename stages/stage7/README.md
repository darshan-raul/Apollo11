---
title: "Stage 7: Orbital Maneuvering — HPA + VPA + Redis cache + practical scheduling"
description: "Add HPA, recommendation-only VPA, Redis cache-aside, PriorityClasses, and an observable taint, affinity, and topology-spread exercise."
---

> **Current verification status:** the context, TLS, and contract fixes in this
> working tree require a fresh runtime lifecycle. Counts below record earlier
> revisions; use the current verifier's summary rather than expecting those totals.

# Stage 7: Orbital Maneuvering

**Status:** Complete; practical scaling closure verified on 2026-08-26.

| Delivery path | Result |
|---|---|
| Helm/dev | **211/211** checks + practical scaling lab, followed by a clean purge |
| Kustomize/dev | **200/200** checks, followed by a clean purge |
| Helm/staging | **211/211** checks with live VPA on 2026-08-25; current render validates statically |

Both refreshed dev purges left zero Apollo namespaces, PVCs, Stage 7
controllers, related CRDs, lab Deployments, worker labels, or taints. Production
and staging Helm/Kustomize renders validate locally; Argo CD static validation
passes for all three environments plus shared observability.

**Goal:** make Apollo Airlines **elastic and cache-friendly**. The search
service — the highest-traffic read path in the system — gains horizontal
auto-scaling on CPU, recommendation-mode vertical auto-scaling, a Redis
cache-aside layer, two PriorityClasses for scheduling priority, and
node-level scheduling behavior (toleration + node affinity + topology spread).
The result
is a service that can ride out traffic spikes without manual intervention.

| | |
|---|---|
| **New concept** | HPA, VPA in `Off` mode, cache-aside, PriorityClass, taint/toleration, node affinity, topology spread, `X-Cache` |
| **Workloads changed** | search — Redis cache, metrics, priority, toleration, affinity, topology spread. Booking + notification — priority only. |
| **Workloads unchanged** | identity, flight, frontend, all StatefulSets, seed Jobs, NetworkPolicies, ServiceAccounts, ConfigMap, Secret, observability stack |
| **New cluster resources** | 2 PriorityClasses, 1 HPA, metrics-server, and—outside dev—1 recommendation-only VPA with recommender/updater controllers |
| **Code changes** | search service: Redis client with bounded startup and lazy recovery, cache GET/SET, cache metrics, `X-Cache: HIT/MISS`, OTEL child spans, and clean shutdown |
| **Verification** | Helm/dev **211/211** + scale 1→3→1 across 2 workers; Kustomize/dev **200/200** |

---

## Architecture additions

### 1. Search service: Redis cache-aside

The search service proxies `flight-service` for every `/api/search` call.
Stage 7 adds a cache-aside layer in front:

```
GET /api/search?origin=BOM&destination=SIN&date=...
    │
    ├─ cache.get  search:BOM:SIN:2026-06-17   ──► Redis (5min TTL)
    │     │
    │     ├── HIT  → return cached body, set X-Cache: HIT
    │     │          increment cache_hits_total
    │     │
    │     └── MISS → forward to flight service
    │                 store result in Redis (SETEX 300)
    │                 set X-Cache: MISS
    │                 increment cache_misses_total
    │
    └─ on Redis error → degrade to MISS (log warning, return live result)
```

**Key design choices:**

- **Graceful degradation and recovery.** Redis connection attempts are bounded
  (10s at startup, 1s from probes/requests). Search serves uncached responses
  when Redis is unavailable and lazily reconnects after Redis recovers. Cache
  GET/SET failures are logged but never fail the user request.
- **OTEL child spans.** The cache lookup is wrapped in a `cache.get` span with a `cache.hit` attribute, so a trace can show the cache effect. A `cache.set` span covers the write. This is a Stage 6 OTEL pattern extended.
- **New Prometheus counters.** `cache_hits_total{service="search"}` and `cache_misses_total{service="search"}` are registered with the same registry as `http_requests_total` (Stage 6) — Grafana can plot hit ratio and a Prometheus alert can fire on low cache effectiveness.
- **Cache key shape.** `search:{origin}:{destination}:{date}` follows the AGENTS.md spec. With 6 airports × 5 dates × 6 airports = ~180 keys, the keyspace is bounded and small.
- **TTL: 5 minutes.** Matches the AGENTS.md spec. Long enough to absorb traffic spikes, short enough that stale flight availability data is bounded.

### 2. HPA: HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: HorizontalPodAutoscaler
metadata:
  name: search-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: search
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
        - type: Pods
          value: 4
          periodSeconds: 30
```

CPU-based, min 2 / max 10. The `behavior` block is the modern k8s pattern:
**scale fast, contract slow**. scaleUp is immediate and can double replicas
every 30s (or add 4 pods per 30s, whichever is greater). scaleDown waits
5 minutes after a CPU dip before killing a pod — without this, a brief
dip would cause a pod kill and a subsequent re-spawn, wasting work.

The HPA controller needs the `metrics.k8s.io` API to compute CPU%. On
a fresh kind cluster this is **not installed by default** — the chart
bundles the upstream metrics-server manifest and `apply.sh` installs it
during phase 4 (the chart's `autoscaling.metricsServer.bundleInstall`
toggle).

### 3. VPA: VerticalPodAutoscaler in `Off` mode

```yaml
apiVersion: autoscaling/v2
kind: VerticalPodAutoscaler
metadata:
  name: search-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: search
  updatePolicy:
    updateMode: "Off"     # recommendations only — no in-place mutation
  resourcePolicy:
    containerPolicies:
      - containerName: search
        minAllowed:    { cpu: 50m,  memory: 64Mi }
        maxAllowed:    { cpu: 1,    memory: 512Mi }
        controlledResources: ["cpu", "memory"]
```

**Why `Off` and not `Auto`?** The standard k8s anti-pattern is to run
HPA on CPU + VPA in `Auto` mode on the same Deployment. The two
controllers fight: VPA lowers `resources.requests` → HPA reads the
lower request, computes CPU as over-utilized → scales out → VPA sees
the new pods as under-utilized → raises requests → HPA scales in.
The system oscillates. The reference k8s design at
<https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/>
says: use one or the other on the same metric, not both.

`Off` mode = the VPA *recommends* resource requests based on observed
usage, but does NOT mutate the Deployment. The operator workflow:

1. HPA scales replicas (immediate response to load)
2. VPA observes per-pod usage over time
3. `kubectl describe vpa search-vpa` shows the `Recommendation` block
4. Operator reads the recommendation, updates the chart's
   `tiers.default.cpu/memory` (or per-service tier), `helm upgrade`

Stage 7 installs the VPA recommender and updater in `kube-system`. It omits the
admission webhook because `updateMode: Off` never mutates pod requests; adding
TLS admission infrastructure would consume resources without participating in
recommendation generation. Dev disables VPA entirely.

### 4. PriorityClass

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: apollo-airlines-app-critical
value: 1000000       # 1M — scheduled before default-priority pods
globalDefault: false
description: "Apollo Airlines app-critical pods (booking, search)."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: apollo-airlines-app-low
value: -100000       # -100K — preempted under node pressure
globalDefault: false
description: "Apollo Airlines app-low pods (notification)."
```

Wired into the Deployments:
- `booking` → `priorityClassName: apollo-airlines-app-critical` (revenue path)
- `search` → `priorityClassName: apollo-airlines-app-critical` (hot read path)
- `notification` → `priorityClassName: apollo-airlines-app-low` (background fan-out)
- `identity` + `flight` + `frontend` → no priorityClassName (default = 0, middle)

### 5. Observable scheduling: toleration, node affinity, and topology spread

```yaml
spec:
  template:
    spec:
      tolerations:
        - key: workload
          operator: Equal
          value: search
          effect: NoSchedule
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: apollo11.io/search-pool
                    operator: In
                    values: [dedicated]
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: search
```

The `toleration` lets search land on nodes tainted with
`workload=search:NoSchedule` — a common pattern in production clusters
where dedicated node groups host specific workloads. The soft node affinity
prefers a worker labeled `apollo11.io/search-pool=dedicated`; it does not make
that worker mandatory if it is unavailable. The topology-spread constraint
then asks the scheduler to keep search replicas balanced across eligible
hostnames with `maxSkew: 1` while retaining `ScheduleAnyway` as a local-lab
escape hatch.

`scripts/scaling-lab.sh` makes all three policies observable. It labels and
taints one worker, restarts search, drives HPA scale-out, proves the resulting
replicas span at least two workers, observes scale-in, and removes the temporary
node metadata.

---

## What changed vs Stage 6

### 1. Code (search service only)

The 4 Go services and 1 Python service were unchanged except search:

- `stages/stage7/code/search/main.go`:
  - + `import "github.com/redis/go-redis/v9/v9"`
  - + bounded Redis startup plus mutex-protected lazy reconnection after a startup race or outage.
  - + `/healthz/ready` returns 200 with `{status, cache}` body; cache state is `ok` / `disabled` / `unreachable`.
  - + `/api/search` cache GET/SET wrap; `X-Cache: HIT|MISS` header; OTEL `cache.get` / `cache.set` child spans; `cache_hits_total` / `cache_misses_total` Prometheus counters.
  - + `redisClient.Close()` in shutdown.
- `stages/stage7/code/search/go.mod`: + `github.com/redis/go-redis/v9 v9.5.1`

### 2. Helm chart

| Template | New / Modify | Purpose |
|---|---|---|
| `templates/config/priorityclass.yaml` | NEW | 2 PriorityClasses (critical, low) |
| `templates/autoscaling/search-hpa.yaml` | NEW | HPA behind `if .Values.autoscaling.search.enabled` |
| `templates/autoscaling/search-vpa.yaml` | NEW | VPA behind `if .Values.vpa.search.enabled` |
| `templates/autoscaling/metrics-server-install.yaml` | NEW | Renders the bundled metrics-server manifest |
| `templates/autoscaling/vpa-install.yaml` | NEW | Renders the recommender/updater bundle outside dev |
| `templates/apps/search.yaml` | Modify | + priority, toleration, node affinity, topology spread, `env REDIS_URL` |
| `templates/apps/booking.yaml` | Modify | + `priorityClassName: apollo-airlines-app-critical` |
| `templates/apps/notification.yaml` | Modify | + `priorityClassName: apollo-airlines-app-low` |
| `values.yaml` | Modify | + `priorityClasses`, `autoscaling`, `vpa`, `redis` blocks |
| `values-dev.yaml` | Modify | `autoscaling.search.minReplicas=1`, `vpa.search.enabled=false` |
| `values-prod.yaml` | Modify | `autoscaling.search.minReplicas=3`, `maxReplicas=20` |

### 3. Bundles

| File | Size | Source |
|---|---|---|
| `bundles/metrics-server-install.yaml` | 205 lines | upstream metrics-server v0.8.1 plus kind's required `--kubelet-insecure-tls` flag |
| `bundles/vpa-install.yaml` | curated from upstream v1.7.0 | CRDs + RBAC + recommender/updater; mutation webhook intentionally omitted for `Off` mode |

### 4. Scripts

- `scripts/apply.sh`: mode-aware Helm/Kustomize installer; pre-installs metrics-server and, outside dev, VPA before submitting their dependent resources.
- `scripts/verify.sh`: Stage 6 contract plus Stage 7 HPA, VPA, priority, scheduling, MISS→HIT, TTL, and cache-metric checks.
- `scripts/scaling-lab.sh`: reversible worker label/taint plus real HTTP load; proves HPA scale-out, topology spread, and scale-in.
- `scripts/teardown.sh`: removes Stage 7 controllers symmetrically; `--purge` also removes namespaces, PVCs, access-stack resources, and related CRDs.

---

## How to use

```bash
cd stages/stage7
bash scripts/build-images.sh        # builds search with redis client
bash scripts/apply.sh --env dev     # installs everything (dev config: VPA off, HPA min=1)
bash scripts/verify.sh --mode helm --env dev
bash scripts/teardown.sh --purge    # cleans up
```

To exercise the cache:

```bash
# In-cluster exec (uses Kubernetes DNS)
kubectl exec -n apollo-airlines-apps deploy/search -- \
  wget -qO- 'http://localhost:8083/api/search?origin=BOM&destination=SIN&date=2026-06-17'
# First call: X-Cache: MISS, cache_misses_total += 1
kubectl exec -n apollo-airlines-apps deploy/search -- \
  wget -qO- 'http://localhost:8083/api/search?origin=BOM&destination=SIN&date=2026-06-17'
# Second call: X-Cache: HIT, cache_hits_total += 1

# Inspect the redis key
kubectl exec -n apollo-airlines-apps redis-0 -- \
  sh -c "redis-cli KEYS 'search:*'"
# => search:BOM:SIN:2026-06-17

kubectl exec -n apollo-airlines-apps redis-0 -- \
  sh -c "redis-cli TTL 'search:BOM:SIN:2026-06-17'"
# => ~290 (decreasing toward 0; 300 = original TTL)
```

To inspect autoscaling:

```bash
kubectl get hpa -n apollo-airlines-apps
# NAME        REFERENCE      TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
# search-hpa  Deployment/search  0%/70%   2         10        2          3m

kubectl describe vpa search-vpa -n apollo-airlines-apps
# VPA is disabled in dev; use staging/prod to create this resource.
# Shows: Recommendation block with Container Recommendations
#         Container Name:  search
#         Target:          {cpu: ..., memory: ...}
#         Lower Bound:     ...
#         Upper Bound:     ...
#         Uncapped Target: ...
```

Run the practical scaling and scheduling exercise after the normal verifier:

```bash
bash scripts/scaling-lab.sh
```

The script requires the recommended Ignition cluster with at least two workers.
It prints the search Pod-to-node mapping and an HPA timeline. For a short,
reliable local demonstration it temporarily changes the HPA CPU target from
70% to 10% and the scale-down window from 300s to 30s. It does **not** alter the
search handler or fake CPU consumption: four short-lived in-cluster clients
make real HTTP requests. An exit trap restores the original HPA policy, deletes
the load generator, and removes the worker label and taint even on failure.

If a previous run was forcibly terminated before its trap ran:

```bash
bash scripts/scaling-lab.sh cleanup
```

---

## Lessons from this stage (read before changing)

1. **HPA + VPA in `Auto` mode on the same metric is an anti-pattern.**
   The two controllers oscillate. The chart uses `Off` mode for VPA —
   recommendations only — which is the standard k8s reference design.
   See <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/>.

2. **Bound retries and recover after startup races.** Both notification and
   search use bounded Redis startup checks. Search additionally retries lazily
   from probes/requests, which matters because Helm may start search before
   Redis is Ready. The first verification run caught this exact race.

3. **Cache miss must degrade gracefully.** A Redis blip must not break
   search. The `cache.get` and `cache.set` calls have 1s timeouts and
   log warnings on error but never fail the user request.

4. **Affinity chooses candidates; topology spread balances replicas.**
   A toleration permits search onto the tainted worker but does not require it.
   The soft node affinity prefers that labeled worker, while topology spread
   scores eligible hostnames to keep `maxSkew: 1`. The scaling lab applies and
   removes the concrete node metadata so these are runtime behaviors, not inert
   YAML examples.

5. **metrics-server is NOT installed on a fresh kind cluster.** The
   HPA controller needs it. The chart bundles the upstream manifest
   (~5KB) so apply.sh doesn't need internet at install time. After
   install, `kubectl top nodes` returns non-empty data and the HPA
   TARGETS column populates within 30s.

6. **VPA is opt-in.** On a local kind cluster the recommender/updater consume
   resources without much history to analyze — `values-dev.yaml` sets
   `vpa.search.enabled=false`, and `apply.sh` skips its bundle. In prod
   (`values-prod.yaml`) it's on.

7. **Cache TTL: 5 minutes.** Matches the AGENTS.md spec. Long enough
   to absorb traffic spikes, short enough that stale flight availability
   data is bounded. The Prometheus `cache_hits_total / (cache_hits_total + cache_misses_total)`
   ratio is the operator's signal — if it drops below 50%, consider
   raising the TTL or the cache size.

8. **Teardown order matters (VPA webhooks).** The teardown script
   removes workload resources before VPA and metrics-server, with `--purge`
   handling cluster-scoped cleanup using the
   same force-delete + finalizer-patch pattern that stage 5/6 used for
   Envoy + MetalLB. Without this, deletion hangs on VPA's
   ValidatingWebhookConfiguration.

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
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get secret apollo-edge-tls \
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

Follow [the repeatable cache benchmark](k6/README.md) before the HPA lab.
