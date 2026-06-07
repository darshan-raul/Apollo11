---
title: "Apollo11 Stage 2 — Handoff Notes"
description: "Plan, current state, and active error for the next agent picking up Stage 2 work."
---

# Stage 2 Handoff — 4-Set Manifest Structure

## TL;DR for the next agent

**Goal:** Build Stage 2 as **4 self-contained manifest sets** under `stages/stage2/setN-*/`. Each set has the same 6 services + 4 infra, but exposes them differently. The learner tears down one set and applies the next.

**Sets:**

| # | Name | Access |
|---|------|--------|
| 1 | `set1-baseline` | NodePort (no controller) — **~90% built, blocked on a NetworkPolicy bug** |
| 2 | `set2-ingress` | Traefik Ingress (DaemonSet on control-plane, NodePort 30443) — **not started** |
| 3 | `set3-gateway-nodeport` | Traefik + Gateway API (HTTPRoute, NodePort 30443) — **not started** |
| 4 | `set4-metallb-gateway` | MetalLB L2 + Traefik LoadBalancer + Gateway — **not started** |

**Active blocker (read this first):** Set 1 has a NetworkPolicy model error that is preventing app pods from becoming Ready. See **"Active Error"** below.

---

## What was decided and approved in this session

User sign-off (verbatim intent):

> "go got all except envoy for gateway api. give detailed instructions in readme to run everything"

This means the plan below was approved. **Do not re-debate these decisions** unless the user changes their mind:

| Decision | Value |
|---|---|
| Number of manifest sets | **4** |
| Ingress controller | **Traefik v3** (DaemonSet on control-plane) |
| Gateway API implementation | **Traefik** (built-in support, not Envoy / not NGINX Gateway Fabric) |
| MetalLB | v0.14+ native speaker mode, L2 advertisement |
| Routing strategy | **Host-based** (5 hostnames, no path stripping) |
| TLS in Stage 2 | **Skip** — defer to Stage 5 |
| Frontend code changes | **None** — VITE_* URLs are baked at build time per set |
| NetworkPolicies | **In all 4 sets** |
| ServiceAccounts | In all 4 sets |
| Headless Services | In all 4 sets (even though StatefulSets are Stage 3) |
| Service type in Sets 2-4 | **ClusterIP** (Traefik routes via cluster IP) |
| Traefik port (Sets 2-3) | **NodePort 30443** |
| Set 4 | Traefik **Service type: LoadBalancer** with MetalLB IP pool |
| Hostnames | `frontend.apollo.local`, `identity.apollo.local`, `flight.apollo.local`, `booking.apollo.local`, `search.apollo.local` |
| DNS for Sets 2-3 | `/etc/hosts` → `127.0.0.1` (5 entries) |
| DNS for Set 4 | nip.io fallback OR dnsmasq (not yet chosen) |
| Directory layout | **4 separate `setN-*/` directories**, each with full self-contained manifests |

---

## Repo context

- Repo: `/home/darshan/projects/Apollo11`
- Stage 1 was reviewed and 3 critical bugs were fixed in commit `1a7e33d`:
  - NodePort conflict (identity vs search both on 30083) — search moved to 30084
  - `VITE_IDENTITY_URL` in build script pointed to wrong port (30080 → 30083)
  - Invalid bcrypt hashes in `identity-init-configmap.yaml` (replaced with verified hashes)
- Stage 1 README was updated to reflect new NodePort layout
- Stage 1 commit pushed to `origin/main` (verified `c3f68ed..1a7e33d main -> main`)
- Cluster: `apollo11` (3 nodes: 1 control-plane + 2 workers) is currently running
- Image registry convention: `apollo11/<service>:latest`, loaded into kind via `kind load docker-image`

---

## Stage 2 directory structure (built so far)

```
stages/stage2/
├── code/                          # Copied from stages/stage1/code (unchanged)
├── set1-baseline/                 # ~90% built — see "Active Error" below
│   ├── README.md                  # ✓ written
│   ├── k8s/
│   │   ├── config/                # ✓
│   │   │   ├── 00-namespaces.yaml    # 3 namespaces
│   │   │   ├── configmap.yaml        # apps + ui (ui has just VITE_*)
│   │   │   └── secrets.yaml          # apps, infra, ui
│   │   ├── serviceaccounts/        # ✓
│   │   │   └── accounts.yaml          # 13 SAs (1 per workload + 3 init jobs)
│   │   ├── networkpolicies/        # ⚠ see "Active Error"
│   │   │   ├── infra-00-default-deny.yaml
│   │   │   ├── infra-allow-dns-egress.yaml
│   │   │   ├── infra-allow-{identity,flight,booking}-app.yaml
│   │   │   ├── infra-allow-init-{identity,flight,booking}-db.yaml
│   │   │   ├── infra-allow-notification-app.yaml
│   │   │   ├── apps-00-default-deny.yaml
│   │   │   ├── apps-allow-dns-egress.yaml
│   │   │   ├── apps-allow-public-ingress.yaml
│   │   │   ├── apps-allow-booking-to-{flight,identity,notification}.yaml
│   │   │   ├── apps-allow-search-to-flight.yaml
│   │   │   ├── ui-00-default-deny.yaml
│   │   │   ├── ui-allow-dns-egress.yaml
│   │   │   └── ui-allow-frontend-public.yaml
│   │   ├── infra/                 # ✓
│   │   │   ├── identity-db/{dep,svc,svc-headless}.yaml
│   │   │   ├── flight-db/{dep,svc,svc-headless}.yaml
│   │   │   ├── booking-db/{dep,svc,svc-headless}.yaml
│   │   │   └── redis/{dep,svc,svc-headless}.yaml
│   │   ├── apps/                  # ✓ — Services are NodePort
│   │   │   ├── identity/{dep,svc}.yaml          # NodePort 30083
│   │   │   ├── flight/{dep,svc}.yaml            # NodePort 30081
│   │   │   ├── booking/{dep,svc}.yaml           # NodePort 30082
│   │   │   ├── search/{dep,svc}.yaml            # NodePort 30084
│   │   │   ├── notification/{dep,svc}.yaml      # ClusterIP
│   │   │   └── frontend/{dep,svc}.yaml          # NodePort 30080
│   │   └── jobs/                  # ✓
│   │       ├── identity-init-configmap.yaml  # bcrypt hashes copied from stage1 (now valid)
│   │       ├── init-identity-db.yaml
│   │       ├── flight-init-configmap.yaml
│   │       ├── init-flight-db.yaml
│   │       ├── booking-init-configmap.yaml
│   │       └── init-booking-db.yaml
│   └── scripts/                   # ✓
│       ├── apply.sh                 # builds + loads + applies layer-by-layer
│       ├── teardown.sh              # deletes 3 namespaces
│       └── verify.sh                # battery of checks
├── set2-ingress/                 # NOT STARTED — empty subdirs
├── set3-gateway-nodeport/        # NOT STARTED — empty subdirs
└── set4-metallb-gateway/         # NOT STARTED — empty subdirs
```

Total files written so far in Stage 2: **57** (`find stages/stage2 -type f -name "*.yaml" -o -name "*.md" -o -name "*.sh" | wc -l`).

---

## Detailed per-set plan

### Set 1: Baseline (NodePort) — current set, ~90% done

**What it teaches:** Namespace isolation, FQDN service discovery, Headless Services, ServiceAccounts, NetworkPolicies (Ingress-only deny by default).

**Access pattern:** `http://localhost:30083/...` (NodePort, same as Stage 1).

**Manifests (all written):** see tree above.

**What's missing:**
- A top-level kustomization.yaml (intentionally skipped — apply.sh drives order)
- Verification: pods are not all Ready (see Active Error)

### Set 2: Traefik Ingress (ClusterIP + Ingress resources)

**What it teaches:** Ingress resource, IngressController, host-based routing, controller selection.

**Access pattern:** `http://identity.apollo.local:30443/...` (Traefik on NodePort 30443).

**Layout:**

```
stages/stage2/set2-ingress/
├── README.md
├── k8s/
│   ├── config/                    # copy of set1's config (3 ns, configmap, secrets)
│   ├── serviceaccounts/           # copy of set1's
│   ├── networkpolicies/           # copy of set1's
│   │                              # but: apps-allow-public-ingress → apps-allow-ingress-from-traefik
│   │                              #      ui-allow-frontend-public → ui-allow-frontend-from-traefik
│   ├── infra/                     # copy of set1's
│   ├── apps/                      # copy of set1's, BUT:
│   │                              #   - identity/flight/booking/search Services are ClusterIP (no nodePort)
│   │                              #   - frontend Service is ClusterIP
│   │                              #   - VITE_* env vars in configmap now use http://*.apollo.local:30443
│   ├── jobs/                      # copy of set1's
│   ├── ingress/
│   │   ├── traefik.yaml           # DaemonSet on control-plane, NodePort 30443, ServiceAccount in kube-system
│   │   ├── clusterrolebinding.yaml
│   │   └── ingress-{frontend,identity,flight,booking,search}.yaml
│   └── scripts/{apply,teardown,verify}.sh
```

**Differences from Set 1:**
1. All app Services drop `type: NodePort` → default ClusterIP
2. VITE_* URLs in ConfigMap (ui namespace) become `http://<svc>.apollo.local:30443`
3. NetworkPolicies: replace `allow-public-ingress` with a tight rule that allows ingress only from pods in `kube-system` with label `app.kubernetes.io/name: traefik` (or equivalent ServiceAccount selector)
4. Add Traefik DaemonSet manifest. Suggested:
   ```yaml
   # Traefik v3 DaemonSet on control-plane, NodePort 30443
   # ServiceAccount: traefik in kube-system
   # args: --providers.kubernetesingress --entrypoints.websecure=false (HTTP only — TLS deferred to Stage 5)
   # Image: traefik:v3.1
   ```
5. Add Ingress resources:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: identity
     namespace: apollo-airlines-apps
     annotations:
       traefik.ingress.kubernetes.io/router.entrypoints: web
   spec:
     ingressClassName: traefik
     rules:
       - host: identity.apollo.local
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: identity
                   port:
                     number: 8080
   ```
6. Frontend image needs to be rebuilt with new VITE_* URLs before the set is runnable:
   ```bash
   docker build -t apollo11/frontend:latest \
     --build-arg VITE_IDENTITY_URL=http://identity.apollo.local:30443 \
     --build-arg VITE_FLIGHT_URL=http://flight.apollo.local:30443 \
     --build-arg VITE_BOOKING_URL=http://booking.apollo.local:30443 \
     --build-arg VITE_SEARCH_URL=http://search.apollo.local:30443 \
     stages/stage2/code/frontend/
   kind load docker-image apollo11/frontend:latest --name apollo11
   ```

### Set 3: Gateway API on NodePort

**What it teaches:** GatewayClass, Gateway, HTTPRoute — the modern replacement for Ingress.

**Access pattern:** same as Set 2 (`http://*.apollo.local:30443/...`), but the controller is configured via Gateway API CRDs.

**Differences from Set 2:**
1. Install Gateway API CRDs first:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
   ```
2. Replace `ingress/` directory with `gateway/`:
   - `gatewayclass.yaml` — defines `traefik` GatewayClass
   - `gateway.yaml` — Gateway with `listeners: [{name: web, port: 30443, protocol: HTTP}]`
   - `httproutes.yaml` — one HTTPRoute per service, attached to the Gateway
3. Traefik args change: `--providers.kubernetesgateway` instead of `--providers.kubernetesingress`
4. HTTPRoute example:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: identity
     namespace: apollo-airlines-apps
   spec:
     parentRefs:
       - name: apollo-gateway
     hostnames: ["identity.apollo.local"]
     rules:
       - backendRefs:
           - name: identity
             port: 8080
   ```

### Set 4: MetalLB + Gateway API

**What it teaches:** MetalLB (L2 mode), LoadBalancer Service, real cluster IPs, IP pool management.

**Access pattern:** `http://*.apollo.local/...` (no port suffix — Traefik gets a real IP).

**Differences from Set 3:**
1. Install MetalLB:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
   ```
2. Add `metallb/` directory:
   - `ip-pool.yaml` — `IPAddressPool` named `apollo-pool`, e.g. `172.18.0.50-172.18.0.100`
   - `l2-advertisement.yaml` — `L2Advertisement` for that pool
3. Traefik Service changes from `type: NodePort` to `type: LoadBalancer`. Wait for MetalLB to assign an IP. That IP becomes the new "front door".
4. VITE_* URLs drop the `:30443` port suffix.
5. README explains how to discover the assigned IP (`kubectl get svc -n kube-system traefik`) and the two DNS options:
   - **nip.io:** `frontend.172-18-0-50.nip.io` (no setup, ugly URLs)
   - **dnsmasq wildcard:** `address=/apollo.local/172.18.0.50` (clean, needs dnsmasq in devbox.json)

---

## Active Error (READ THIS FIRST)

### Symptom

After applying Set 1 with `bash scripts/apply.sh`:

```
apollo-airlines-apps    booking-598d985b59-gf7vg    0/1   Running
apollo-airlines-apps    flight-64476dcc5f-t6pwh     0/1   Running
apollo-airlines-apps    identity-7ff7df698c-mnrg2   0/1   Running
apollo-airlines-apps    notification-5b57c9f495-25pwd  0/1  Running
apollo-airlines-apps    search-7b5dcdd58b-2pmjs     1/1   Running    ← only search works
apollo-airlines-apps    search-7b5dcdd58b-r6vjt     1/1   Running    ← only search works
```

DB pods, redis, init jobs, search, and frontend all come up fine. But identity, flight, booking, and notification never become Ready.

### Diagnosis

I traced this down to a **NetworkPolicy model issue**. Quick background:

- `identity-db` (infra ns) is reachable from `identity` (apps ns) via FQDN `identity-db.apollo-airlines-infra.svc.cluster.local`.
- DNS works (verified: `python3 -c "import socket; print(socket.gethostbyname('identity-db.apollo-airlines-infra.svc.cluster.local'))"` returned `10.96.109.8`).
- BUT the actual TCP connect from the identity pod times out:
  ```python
  socket.create_connection(('identity-db.apollo-airlines-infra.svc.cluster.local', 5432), timeout=5)
  # → socket.timeout: timed out
  ```
- The TCP connection is being dropped somewhere.

### What I tried

1. **First attempt:** Default-deny on both Ingress AND Egress. Result: identity → identity-db blocked because the apps-ns default-deny blocked egress on the apps side. (Ingress rule on identity-db in infra ns was correct, but egress from identity pod in apps ns was blocked by the apps default-deny.)

2. **Second attempt:** Changed all default-deny policies to Ingress-only (removed Egress from `policyTypes`). Expected the apps pods to be able to initiate outgoing connections.

3. **Cleanup:** Deleted the leftover `default-deny-all` policies from the cluster (they were still there from the first apply).

4. **Current state:** Old pods are in `CrashLoopBackOff`, new pods are `Running` but `0/1` (not Ready).

### What I think is still wrong

I did NOT verify the connectivity is fixed after step 3. The user aborted the verification command. The pods in the cluster are still showing the old state (old `CrashLoopBackOff` replicas + new `Running 0/1` replicas that may or may not have become Ready after the netpol cleanup).

### Reproduction steps for the next agent

```bash
# 1. Confirm cluster is up
kubectl get nodes

# 2. Confirm set 1 is currently applied
kubectl get ns | grep apollo-airlines

# 3. Check current netpol state
kubectl get netpol -A | grep apollo

# 4. Confirm old default-deny-all is gone (should not appear in output above)
kubectl get netpol -A | grep "default-deny-all"

# 5. Force a fresh rollout of all app deployments
kubectl rollout restart deployment -n apollo-airlines-apps
kubectl rollout restart deployment -n apollo-airlines-ui

# 6. Wait 30s and check status
sleep 30
kubectl get pods -A | grep apollo-airlines

# 7. If identity still 0/1, exec in and test the DB connection
POD=$(kubectl get pod -n apollo-airlines-apps -l app=identity -o name | grep -v CrashLoop | head -1)
kubectl exec -n apollo-airlines-apps $POD -- python3 -c "
import socket
s = socket.create_connection(('identity-db.apollo-airlines-infra.svc.cluster.local', 5432), timeout=5)
print('TCP OK')
s.close()
"

# 8. If TCP times out, the issue is still network policy. Check:
kubectl describe netpol -n apollo-airlines-infra allow-identity-app-to-identity-db
# Make sure podSelector/namespaceSelector match exactly.
```

### What the fix likely is

The most likely fix is one of:

**A)** Add explicit egress allow rules on the apps side. The current setup has default-deny-ingress but no explicit egress allow, so by default egress should be allowed. But for some CNI implementations (Calico, Cilium), having a `default-deny-ingress` policy can implicitly affect egress. Worth confirming by testing with NO policies at all:

```bash
# Quick test: delete all netpols and see if connectivity works
kubectl delete netpol --all -n apollo-airlines-apps
kubectl delete netpol --all -n apollo-airlines-infra
kubectl delete netpol --all -n apollo-airlines-ui
# Then restart identity pod and test
```

If that fixes it, the next agent can re-add policies one at a time to find the bad one.

**B)** The `from` clause in `allow-identity-app-to-identity-db` might be wrong. Specifically, the `namespaceSelector.matchLabels` might be matching too narrowly. Try replacing with just `podSelector`:

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: identity
    ports:
      - protocol: TCP
        port: 5432
```

But that wouldn't work for cross-namespace (podSelector alone only matches pods in the same namespace as the policy).

**C)** The DNS-based FQDN is somehow being resolved to the wrong IP. Test by running:

```bash
kubectl exec -n apollo-airlines-apps <identity-pod> -- python3 -c "
import socket
print(socket.gethostbyname('identity-db.apollo-airlines-infra.svc.cluster.local'))
"
# Should print 10.96.x.x (cluster IP of identity-db Service)
# Then test TCP:
kubectl exec -n apollo-airlines-apps <identity-pod> -- python3 -c "
import socket
s = socket.create_connection(('10.96.x.x', 5432), timeout=5)
print('TCP OK')
"
```

If FQDN resolves but TCP to cluster IP times out, it's the NetworkPolicy. If FQDN resolves AND TCP to cluster IP works, then there's a stale DNS or kube-proxy issue.

---

## Key file paths the next agent will need

### Existing
- `stages/stage1/README.md` — Stage 1 reference (NodePort pattern, working state)
- `stages/stage1/k8s/apps/identity/identity-dep.yaml` — base identity deployment (no FQDN, single ns)
- `stages/stage1/scripts/build-images.sh` — image build script
- `stages/ignition/kind-config.yaml` — kind cluster config with extraPortMappings 30080-30084 (and now 30084)
- `stages/ignition/kind-config-single.yaml` — single-node variant

### Stage 2 in progress
- `stages/stage2/set1-baseline/` — baseline set (90% done, see Active Error)
- `stages/stage2/set2-ingress/`, `set3-gateway-nodeport/`, `set4-metallb-gateway/` — empty subdirs
- `stages/stage2/code/` — code copy from stage 1 (unchanged)

### Tools / external
- Traefik v3 docs: https://doc.traefik.io/traefik/v3.1/
- Traefik + Gateway API: https://doc.traefik.io/traefik/v3.1/providers/kubernetes-gateway/
- Traefik + Ingress: https://doc.traefik.io/traefik/v3.1/providers/kubernetes-ingress/
- Gateway API CRDs (standard channel): https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
- MetalLB v0.14 native: https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

---

## How to pick up (suggested workflow)

1. **Read the Active Error section above.** Confirm the current state of the cluster, then verify whether the fix landed after I deleted the stale `default-deny-all` policies.
2. **Get Set 1 fully working** — pods Ready, smoke tests pass via `verify.sh`. This is the foundation for sets 2-4.
3. **Tear down Set 1 cleanly** with `teardown.sh`.
4. **Copy Set 1 → Set 2** (`cp -r set1-baseline/. set2-ingress/`).
5. **Modify Set 2 to add Traefik + Ingress** per the Set 2 plan above.
6. **Repeat for Sets 3 and 4.**
7. **Write the master `stages/stage2/README.md`** with the progression guide and links to each set.

---

## Constraints to remember

From AGENTS.md and the SPEC:

- No emojis in files unless the user asks
- No comments in code unless asked
- YAML frontmatter on docs
- Don't auto-commit; commit only when the user asks
- 4 spaces of indentation, no tabs
- k8s manifests use `app: <name>` and `app.kubernetes.io/part-of: apollo-airlines` labels where possible
- Service type drops from NodePort → ClusterIP in Sets 2/3/4
- Traefik runs as DaemonSet on the control-plane node (for Sets 2/3), so the hostPort on the DaemonSet is critical for kind's port mapping to work
- The frontend SPA URLs are baked at build time — every set needs a fresh `docker build` with new `--build-arg VITE_*_URL=...` before being runnable
- Traefik ServiceAccount needs ClusterRole + ClusterRoleBinding for ingress-class lookup (standard kube-system pattern)

---

## Last conversation context

User's last action: "ill have to end this session, can you save the detailed plan and error you are facing in handoff.md for next agent to take up"

User then said "continue" — interpreting this as "continue with the handoff" given the context. This file is the handoff.
