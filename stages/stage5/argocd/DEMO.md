---
title: "ArgoCD GitOps Demo 101"
description: "End-to-end walkthrough of installing ArgoCD, bootstrapping the 3 Apollo Applications, syncing the workloads, and demonstrating drift detection — on a local kind cluster."
---

# ArgoCD GitOps Demo 101

**Audience:** someone who has finished Stage 5 Helm / Kustomize and wants to
see the workloads managed declaratively by ArgoCD instead of `helm install`.

**Time:** ~30 minutes if you have a kind cluster ready; ~45 if you also need
to provision the cluster and build images.

**What you'll end up with:**

- ArgoCD v2.13.2 running in your cluster
- 1 AppProject (`apollo-airlines`) restricting scope
- 3 Applications (`apollo11-dev`, `apollo11-staging`, `apollo11-prod`)
- The Stage 5 Helm chart auto-syncing into the cluster
- The UI accessible via `kubectl port-forward`

---

## 0. Prerequisites

```bash
# 0.1 You are in the Apollo11 repo
cd ~/projects/Apollo11
git rev-parse --is-inside-work-tree  # → true

# 0.2 Your kind cluster is up
kind get clusters
# → apollo11

kubectl cluster-info
# → Kubernetes control plane is running at https://127.0.0.1:xxxxx

# 0.3 You have the devbox shell (or the tools installed another way)
devbox shell
which kubectl helm argocd
# → /home/<you>/.local/bin/...
# → /home/<you>/.local/bin/...
# → /home/<you>/.local/bin/...
```

If `which argocd` returns nothing: `brew install argocd` or grab the binary
from https://argo-cd.readthedocs.io/en/stable/cli_installation/.

> **One thing to confirm before starting:** the `repoURL` in
> `applications/*.yaml` is `https://github.com/darshan/Apollo11`. If your
> fork is at a different URL, set `GITOPS_REPO` or pass
> `--repo-url https://github.com/<you>/Apollo11` to `bootstrap.sh`.

---

## 1. Stage 5 baseline (2 minutes)

Make sure the chart and code snapshot are in place:

```bash
ls stages/stage5/
# → code/  helm/  overlays/  scripts/  README.md  argocd/

ls stages/stage5/argocd/
# → README.md  DEMO.md  install.sh  uninstall.sh  projects/  applications/  scripts/
```

If `argocd/` is missing, you're on an older checkout. The submodule-style
shape is just a regular directory — copy it in or re-clone.

---

## 2. Install ArgoCD (3 minutes)

```bash
cd stages/stage5/argocd
bash install.sh
```

**What you should see (trimmed):**

```
▶ 0/6 Checking cluster
✓ cluster reachable
▶ 1/6 Fetching ArgoCD v2.13.2 install manifest from upstream
✓ fetched 1550 lines
▶ 2/6 Creating argocd namespace
✓ namespace argocd
▶ 3/6 Applying ArgoCD manifests
deployment.apps/argocd-server created
...
▶ 4/6 Waiting for argocd-server
✓ argocd-server Ready
▶ 5/6 Waiting for argocd-application-controller
✓ argocd-application-controller Ready
▶ 6/6 Fetching initial admin password
✓ initial admin password: <random 16 chars>
```

> **Save the password** — it's only shown once. It's the name of the
> `argocd-server` pod.

**Sanity check:**

```bash
kubectl get pods -n argocd
# NAME                                READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0     1/1     Running   0          30s
# argocd-redis-...                    1/1     Running   0          30s
# argocd-repo-server-...              1/1     Running   0          30s
# argocd-server-...                   1/1     Running   0          30s
```

**Gotchas:**

- *"image pull error"* — your kind cluster doesn't have internet egress
  for quay.io / ghcr.io. Fix: configure a proxy in `~/.docker/daemon.json`
  or use a kind node image that has the registries in
  `containerd.config.toml`.
- *"argocd-server not Ready after 120s"* — check
  `kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server`.
  Common cause: webhook failed because the cert isn't ready.

---

## 3. Bootstrap the AppProject + 3 Applications (2 minutes)

```bash
cd stages/stage5/argocd
bash scripts/bootstrap.sh --sync
```

`--sync` force-syncs dev and staging immediately. (We do **not** sync
prod in this demo — prod is human-gated.)

**What you should see (trimmed):**

```
▶ 0/6 Checking cluster + ArgoCD
✓ ArgoCD is installed
▶ 1/6 Creating tenant namespace apollo-airlines
✓ namespace apollo-airlines
▶ 2/6 Registering AppProject
appproject.argoproj.io/apollo-airlines created
✓ AppProject apollo-airlines
▶ 3/6 Registering Applications
application.argoproj.io/apollo11-dev created
application.argoproj.io/apollo11-staging created
application.argoproj.io/apollo11-prod created
✓ Application apollo11-dev
✓ Application apollo11-staging
✓ Application apollo11-prod
▶ 4/6 Waiting for ArgoCD to pick up the new Applications
✓ apollo11-dev reconciled (gen=1)
✓ apollo11-staging reconciled (gen=1)
✓ apollo11-prod reconciled (gen=1)
▶ 5/6 Force-syncing dev + staging
...
```

**Sanity check:**

```bash
kubectl get applications -n apollo-airlines
# NAME                SYNC STATUS   HEALTH STATUS
# apollo11-dev        Synced        Healthy
# apollo11-staging    Synced        Healthy
# apollo11-prod       OutOfSync      Healthy
```

`apollo11-prod` is `OutOfSync` because manual sync is its policy. That's
correct — see section 6.

---

## 4. Watch the workloads come up (5–10 minutes)

```bash
# 4.1 Tail the ArgoCD app controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f --tail=20

# 4.2 In another terminal: watch workloads
kubectl get pods -n apollo-airlines-apps -w
```

You should see, in order:

1. `statefulset/identity-db-0`, `flight-db-0`, `booking-db-0`, `redis-0`
   transition Pending → ContainerCreating → Running
2. `job/seed-identity-db`, `seed-flight-db`, `seed-booking-db` Complete
3. `deployment/identity`, `flight`, `booking`, `search`, `notification`
   come up
4. In `apollo-airlines-ui`, `deployment/frontend` comes up
5. ArgoCD flips `health.status` from `Progressing` to `Healthy`

> **First-time slowness:** the StatefulSets each `initdb` from the
> ConfigMap-mounted SQL, which is ~3s each. Plus image pull. Total:
> 2-3 minutes for the data plane, then ~30s for the apps.

**Verify end-to-end:**

```bash
# 4.3 Run the Stage 5 verify suite (should pass for dev/staging workloads)
cd ../../  # back to stages/stage5
bash scripts/verify.sh

# 4.4 Run the ArgoCD-specific verify suite
cd argocd
bash scripts/verify.sh
```

Expected: both pass.

---

## 5. Open the UI (2 minutes)

```bash
# 5.1 Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PF_PID=$!

# 5.2 Open the UI
xdg-open https://localhost:8080  # Linux
# or:  open https://localhost:8080  # macOS

# Accept the self-signed cert warning
# Username: admin
# Password: <the one you saved from install.sh>
```

**What you should see in the UI:**

- 3 application cards: `apollo11-dev`, `apollo11-staging`, `apollo11-prod`
- Click `apollo11-dev` → see the resource tree: 3 StatefulSets, 6
  Deployments, 7 Services, 2 ConfigMaps, 1 Secret, 2 PDBs, 1 Gateway, 6
  HTTPRoutes, 1 IPAddressPool, 1 L2Advertisement
- Click "App Details" → "Sync Status" → "Synced"
- Click "History" → see 1 sync (the one `--sync` triggered)
- Click "Details" → see `repoURL`, `revision`, `values-dev.yaml` listed

**Log in via CLI:**

```bash
argocd login localhost:8080 --username admin --password "$PASSWORD" --insecure
# 'admin' logged in to context 'localhost:8080'

argocd app list -n apollo-airlines
# NAME                SYNC STATUS   HEALTH STATUS
# apollo11-dev        Synced        Healthy
# apollo11-staging    Synced        Healthy
# apollo11-prod       OutOfSync      Healthy
```

---

## 6. The "wow" moment: GitOps reconciliation (5 minutes)

This is the demo. It's the single most important thing to internalize.

### 6.1 Out-of-band change → ArgoCD reverts

```bash
# 6.1.1 Bump the booking deployment's image tag by hand
kubectl set image deployment/booking booking=apollo11/booking:v999 \
    -n apollo-airlines-apps
# → deployment.apps/booking image updated

# 6.1.2 Watch ArgoCD revert it (within ~3 minutes)
kubectl get application apollo11-dev -n apollo-airlines -w
# NAME             SYNC STATUS   HEALTH STATUS
# apollo11-dev     Synced        Healthy
# apollo11-dev     OutOfSync     Healthy      ← ArgoCD detected drift
# apollo11-dev     Synced        Healthy      ← selfHeal kicked in

# 6.1.3 Confirm the image is back
kubectl get deployment booking -n apollo-airlines-apps \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
# → apollo11/booking:dev  (back to what the chart says)
```

This is **the** GitOps promise. `kubectl apply` is no longer a
moveable feast — the cluster is converging on Git, not on whatever the
last person typed.

### 6.2 In-band change → ArgoCD syncs

```bash
# 6.2.1 Edit the values file
$EDITOR stages/stage5/helm/apollo11/values-dev.yaml
# ... change image.tag from `dev` to `dev-2025-06-11` ...

# 6.2.2 Commit + push
git add stages/stage5/helm/apollo11/values-dev.yaml
git commit -m "dev: bump tag to dev-2025-06-11"
git push

# 6.2.3 Watch ArgoCD pick it up
# (ArgoCD polls the repo every 3 minutes by default. For an immediate
# refresh, do `argocd app sync apollo11-dev --grpc-web`)

kubectl get pods -n apollo-airlines-apps -l app=booking -w
# You should see a new pod come up with the new image.

# 6.2.4 Inspect the history
argocd app history apollo11-dev --grpc-web
# ID  DATE                         REVISION
# 0   2025-06-11T10:00:00+00:00    <sha-of-initial-commit>  (initial)
# 1   2025-06-11T10:05:23+00:00    <sha-of-bump-commit>     (dev tag bump)
```

### 6.3 Rollback via ArgoCD

```bash
# 6.3.1 Realize the bump was wrong
argocd app rollback apollo11-dev --grpc-web
# → Rolled back to revision 0

# 6.3.2 Watch the cluster converge
kubectl get pods -n apollo-airlines-apps -l app=booking -w
# Pod rolls back to the previous image.

# 6.3.3 The rollback is a sync — it's recorded in history
argocd app history apollo11-dev --grpc-web
# ID  DATE                         REVISION
# 0   ...                          (initial)
# 1   ...                          (dev tag bump)
# 2   ...                          (rollback to 0)
```

Note: the rollback is just another sync. The `targetRevision` of the
Application (HEAD of the repo) hasn't changed — the cluster state
diverged from the repo briefly, and we synced it back.

---

## 7. Prod: manual sync (5 minutes)

```bash
# 7.1 Check prod's status
argocd app get apollo11-prod --grpc-web
# ...
# Sync Policy:     <none>     ← manual
# Sync Status:     OutOfSync
# Health Status:   Healthy

# 7.2 Why is it OutOfSync? Compare the rendered chart with the cluster
argocd app diff apollo11-prod --grpc-web
# Shows every difference between desired (repo) and live (cluster).
# In our setup, prod targets tag=v1.0.0 but no image with that tag
# exists in our local kind cluster, so the Deployment's pod template
# would fail to pull. That's expected — see "Adoption gotcha" below.

# 7.3 To sync anyway (in a real cluster with the v1.0.0 image in GHCR):
argocd app sync apollo11-prod --grpc-web
# This would: pull the chart with values-prod.yaml, render, apply.

# 7.4 In our local kind, let's just promote dev's tag to prod for the
# sake of the demo. (Don't do this in real life — pin prod to a
# release tag.)

# Edit prod.yaml to use :dev
sed -i 's|value: v1.0.0|value: dev|' applications/prod.yaml
kubectl apply -f applications/prod.yaml
# ArgoCD picks up the change within 3 minutes. Or:
argocd app get apollo11-prod --grpc-web --refresh
argocd app sync apollo11-prod --grpc-web
```

> **Adoption gotcha:** If you already ran
> `stages/stage5/scripts/apply.sh` *before* registering the Application,
> the Application will see the existing helm-managed resources as
> OutOfSync (because ArgoCD sees a *different* owner label than what the
> Application registered). Fix: `argocd app sync apollo11-prod --replace`
> which adopts them, or remove the helm release first
> (`stages/stage5/scripts/teardown.sh`) and let ArgoCD create them
> fresh. **For this demo, the cleanest path is: bootstrap first, never
> run apply.sh separately.**

---

## 8. Self-heal demo (drift detection) (2 minutes)

This is a built-in check in `scripts/verify.sh`. The script:

1. Picks the `booking` pod in `apollo-airlines-apps`
2. `kubectl delete pod` (within 5s of the auto-replace, since replicas=2)
3. Waits 5s
4. Verifies the pod count is restored

```bash
bash scripts/verify.sh
# Last section:
# ▶ 5/5 Drift detection (delete a pod, watch ArgoCD re-create it)
#   deleting pod booking-7c5b9f8d9d-xxxxx...
# ✓ booking pods present after deletion (2)
```

The deployment's replicaset controller does most of the work, but the
point is: even if you'd deleted the *Deployment* itself, ArgoCD would
recreate it within 3 minutes (selfHeal=true on dev).

To test that more dramatic case:

```bash
kubectl delete deployment booking -n apollo-airlines-apps
sleep 200  # wait for selfHeal
kubectl get deployment booking -n apollo-airlines-apps
# → booking is back, with 1/1 ready
```

---

## 9. Teardown (2 minutes)

```bash
cd stages/stage5/argocd

# 9.1 Remove the 3 Applications. ArgoCD prunes the workloads
#     (because of the resources-finalizer). AppProject + ArgoCD stay.
bash scripts/teardown.sh

# 9.2 If you want to nuke everything ArgoCD owns:
bash scripts/teardown.sh --full

# 9.3 Nuclear option — also delete cluster-scoped CRDs
bash scripts/teardown.sh --purge
```

Verify the cluster is clean:

```bash
kubectl get applications -n apollo-airlines
# → No resources found

kubectl get ns | grep -E 'argocd|apollo-airlines'
# After --full or --purge: no output
```

---

## Troubleshooting playbook

| Symptom | Cause | Fix |
|---|---|---|
| `argocd-server` CrashLoopBackOff | cert-manager / webhook race | `kubectl logs -n argocd argocd-server-0 -c argocd-server` for the actual error |
| `application/apoll11-dev` shows `Unknown` source | GitHub rate-limited the repoServer | `argocd app get apollo11-dev` and check `status.conditions` |
| `OutOfSync` after `bootstrap.sh --sync` finished | drift introduced between sync and observe (e.g. controller updated something) | `argocd app sync apollo11-dev --grpc-web` |
| `Prune` deleted too much | Application's valueFiles was widened, ArgoCD pruned the old set | `argocd app history apollo11-dev --grpc-web` → rollback |
| Helm template render fails | chart's CRDs not yet installed | wait 30s, or `argocd app sync apollo11-dev --retry` |
| `image pull` errors in pods | image not in kind's containerd cache | `kind load docker-image apollo11/booking:dev --name apollo11` |
| Application is "Progressing" forever | one of the pods is CrashLoopBackOff | `kubectl get pods -A` to find it, then `kubectl logs` + `kubectl describe` |
| Self-heal reverts your emergency `kubectl edit` | that's the feature, not a bug | for prod, set `selfHeal: false` (we did) — manual sync only |

---

## What you learned

| Concept | What it means in practice |
|---|---|
| **Git is the source of truth** | `kubectl apply` is a temporary override; `git push` is the durable change |
| **AppProject = security boundary** | even with compromised apps, blast radius is 2 namespaces |
| **Sync policy = automation contract** | dev/staging auto-sync, prod manual — you decide per env |
| **selfHeal = drift detector** | the cluster converges on Git, not on the last human edit |
| **prune = resource hygiene** | when you remove a resource from the chart, the cluster follows |
| **history = audit log** | every sync, every rollback, every diff is recorded |

---

## Where this goes next

- **Stage 6 (Mission Ops):** ArgoCD's notification controller sends Slack
  alerts on sync failures. Add a `Notification` subscription to the
  AppProject.
- **Stage 8 (Command Module):** OPA Gatekeeper policies are enforced
  on Application sync — e.g. "no Pods without a `runAsNonRoot` SA."
- **Stage 9 (Lunar Orbit):** Same chart, multi-cluster. Add
  `ApplicationSet` with a `cluster` generator that fans out to EKS + GKE.
- **Stage 10 (Mission Extensions):** Argo Rollouts replaces Deployments
  for the booking and search services. The Application still points at
  the chart; the chart's templates switch to `Rollout` kinds for those
  two services.
