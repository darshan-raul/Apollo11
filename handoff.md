---
title: "Apollo11 — Handoff Notes"
description: "Stage 2 complete across all 4 sets. Summary for the next agent."
---

# Apollo11 — Handoff Notes

## Stage 2 Status: COMPLETE

All 4 sets built, applied, and verified end-to-end. Pods Ready, smoke
tests pass with real JWTs returned through the controllers.

| Set | Access | Verify |
|-----|--------|--------|
| 1. `set1-baseline` | NodePort (no controller) | **25/25 pass** |
| 2. `set2-ingress` | Traefik v3 Ingress + NodePort 30443 | **25/25 pass** |
| 3. `set3-gateway-nodeport` | Envoy Gateway API + port-forward | **26/26 pass** |
| 4. `set4-metallb-gateway` | Envoy Gateway API + MetalLB L2 | **28/28 pass** |

Each set has a per-set README with prerequisites, apply/teardown/verify
steps, smoke tests, and concept questions. See
`stages/stage2/README.md` for the master overview.

---

## 2-Namespace Decision

User (in this session) corrected the original 3-namespace plan to **2 namespaces**:

| | Old (3 ns) | New (2 ns) |
|---|---|---|
| Namespaces | `apollo-airlines-infra`, `apollo-airlines-apps`, `apollo-airlines-ui` | `apollo-airlines-apps`, `apollo-airlines-ui` |
| Where infra lives | `infra` ns | `apps` ns |
| Where init jobs live | `infra` ns | `apps` ns |
| DB hostname for backend | `identity-db.apollo-airlines-infra.svc.cluster.local` | `identity-db` (short name) |
| FQDN teaching | Multiple cross-namespace calls | Mostly intra-namespace |

**Decision rationale:** Cleaner, less ceremony, avoids init-job-namespace-mismatch
bugs.

---

## Critical insights from this session

### 1. Envoy Gateway v1.2.4 specifics
- The bundled `install.yaml` is **1.5MB** — must use `kubectl apply --server-side`
  (client-side apply would exceed the 256KB last-applied-config annotation limit)
- The `install.yaml` does **NOT** create a `GatewayClass` resource. You must
  create it manually:
  ```yaml
  apiVersion: gateway.networking.k8s.io/v1
  kind: GatewayClass
  metadata:
    name: eg
  spec:
    controllerName: gateway.envoyproxy.io/gatewayclass-controller
  ```
- `spec.infrastructure.serviceOverride` is a v1.3+ feature, NOT in v1.2.4
- The auto-created Envoy Service is `type: LoadBalancer` by default — patch to
  `ClusterIP` for kind/port-forward (Set 3) or use MetalLB (Set 4)
- Cross-namespace HTTPRoute attachments need:
  1. Explicit `parentRef.namespace: <gateway-ns>` in the HTTPRoute
  2. A `ReferenceGrant` in the target namespace allowing cross-namespace refs

### 2. MetalLB specifics
- v0.14.5 native speaker mode is the right choice
- L2 mode (ARP/NDP) works without router config
- The bundled `metallb-native.yaml` is ~1900 lines — use `kubectl apply --server-side`
- Must use `--force-conflicts` because the webhook manages its own CA bundle
- The IP pool range must NOT overlap with kind node IPs
- Default pool `172.18.0.50-100` works on default kind docker network
- After apply, the webhook isn't ready immediately — wait for the controller
  pod to be 1/1 before creating IPAddressPool

### 3. kindnet does NOT enforce NetworkPolicies
- The `k8s/networkpolicies/` manifests in each set are reference only
- `apply.sh` does NOT apply them (they're no-ops without a real policy-aware CNI)
- README explains this prominently in each set

### 4. Init job namespace bug (FIXED)
- The 3-namespace plan had init jobs in `infra` ns but DBs were later moved to
  `apps` ns. There was a window where init jobs had `namespace: apollo-airlines-apps`
  but should have been in `apollo-airlines-infra`. This was a copy-paste bug.
- **Resolution:** 2-namespace plan. Init jobs and DBs are both in
  `apollo-airlines-apps`. Bug class is gone.

### 5. Service patching rules for Sets 2/3
- Set 1 services had `type: NodePort + nodePort: 30xxx`
- Sets 2/3/4 services drop the `nodePort` field and add `type: ClusterIP`
- If you forget to remove the `nodePort` field, kubectl rejects the
  apply with "may not be used when `type` is 'ClusterIP'"

---

## File layout (final)

```
stages/stage2/
├── code/                        # shared source (no changes from stage 1)
├── README.md                    # master overview, progression guide
├── set1-baseline/               # NodePort (no controller)
├── set2-ingress/                # Traefik v3 + Ingress + NodePort 30443
├── set3-gateway-nodeport/       # Envoy Gateway + port-forward
└── set4-metallb-gateway/        # Envoy Gateway + MetalLB
```

Each set has ~30-50 files. Total Stage 2: ~150 files.

---

## Cross-cutting decisions

| Decision | Value | Source |
|---|---|---|
| Traefik version | v3.1 | User |
| Envoy Gateway version | v1.2.4 | User |
| MetalLB version | v0.14.5 native | User |
| GatewayClass name | `eg` | Envoy default |
| Hostnames | `<svc>.apollo.local` | User |
| Namespaces | `apps`, `ui` (2 not 3) | User |
| Number of sets | 4 | User |
| TLS in Stage 2 | None | User |
| Frontend code changes | None | User |
| Teardown behavior | Tear down EVERYTHING | User |
| NetworkPolicy auto-apply | No (kindnet doesn't enforce) | Agreed |
| /etc/hosts automation | Print only, no auto-modify | User |
| Image rebuild | Per-set build-images.sh | User |
| Service account | Same name across all sets | Established |

---

## What's next (Stage 3: Mission Data)

The next stage introduces persistent storage:
- Convert `identity-db`, `flight-db`, `booking-db` to StatefulSets
- Wire the existing Headless Services to StatefulSet `serviceName`
- Init jobs become init containers inside the StatefulSet pod
- PVCs (1Gi) per pod
- ServiceAccount already exists for each DB (added in Stage 2)

The Stage 2 manifests form a solid foundation — Stage 3 just swaps
Deployments for StatefulSets and adds PVCs.
