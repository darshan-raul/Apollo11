# Stage 3 Author Before Bootstrap: StatefulSet + Headless Service

Before bootstrapping the full Stage 3 fleet with `stages/stage3/scripts/apply.sh`, practice converting `booking-db` from a stateless `Deployment` + `emptyDir` into a `StatefulSet` backed by a `volumeClaimTemplates` PVC and a headless `Service`.

## Goal

Convert the starter `booking-db` manifests into:

1. A `StatefulSet` (`booking-db` in namespace `apollo-airlines-apps`) with:
   - `spec.serviceName: booking-db-headless`
   - `PGDATA: /var/lib/postgresql/data/pgdata` (so the official Postgres entrypoint runs `/docker-entrypoint-initdb.d/*.sql` once on an empty PVC and skips it on restarts)
   - `init-script` ConfigMap (`booking-db-init-script`) mounted at `/docker-entrypoint-initdb.d`
   - `volumeClaimTemplates` requesting `1Gi` with `accessModes: ["ReadWriteOnce"]` for `pg-data` (removing `emptyDir`)
2. A headless `Service` (`booking-db-headless` in `apollo-airlines-apps`) with `clusterIP: None`, selector matching the StatefulSet pod labels (`app: booking-db`), and port `5432`.
3. The existing regular `ClusterIP` Service (`booking-db`) kept intact so application Pods (`booking`) continue connecting to `booking-db:5432` unchanged.

## Workflow

```bash
# 1. Copy starter manifests into your git-ignored work/ directory
mkdir -p learner-work/stage3/work
cp learner-work/stage3/starter/* learner-work/stage3/work/

# 2. Convert booking-db-dep.yaml -> booking-db-sts.yaml (remove the Deployment)
#    and add booking-db-svc-headless.yaml in learner-work/stage3/work/

# 3. Validate your work
bash learner-work/stage3/check.sh
```

## Check Commands

```bash
# Validate learner-work/stage3/work/ (default)
bash learner-work/stage3/check.sh

# Validate any custom directory
bash learner-work/stage3/check.sh path/to/manifests

# Verify the reference solution (exits 0)
bash learner-work/stage3/check.sh --solution
```

Once `check.sh` passes, compare your manifests against `stages/stage3/k8s/apps/booking-db/` and proceed with `cd stages/stage3 && ./scripts/apply.sh`.
