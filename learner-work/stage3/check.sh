#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf 'Usage: %s [--solution | <manifest-dir>]\n' "$0"
  printf '  --solution       Validate the reference solution directory\n'
  printf '  <manifest-dir>   Validate a custom manifest directory (default: work/)\n'
}

TARGET_DIR=""
USE_SOLUTION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --solution)
      USE_SOLUTION=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "${TARGET_DIR}" ]]; then
        TARGET_DIR="$1"
        shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ "${USE_SOLUTION}" == true && -n "${TARGET_DIR}" ]]; then
  printf 'Cannot combine --solution with a directory argument.\n' >&2
  exit 2
fi

if [[ "${USE_SOLUTION}" == true ]]; then
  TARGET_DIR="${SCRIPT_DIR}/solution"
elif [[ -z "${TARGET_DIR}" ]]; then
  TARGET_DIR="${SCRIPT_DIR}/work"
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
  printf '[FAIL] Directory does not exist: %s\n' "${TARGET_DIR}" >&2
  printf 'Copy starter/ to work/ first: mkdir -p %s/work && cp %s/starter/* %s/work/\n' \
    "${SCRIPT_DIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf '[FAIL] python3 is required to validate YAML manifests.\n' >&2
  exit 1
fi

python3 - "${TARGET_DIR}" <<'PY'
import pathlib
import sys
import yaml

target_dir = pathlib.Path(sys.argv[1])
yaml_files = sorted(
    p for p in target_dir.iterdir()
    if p.is_file() and p.suffix.lower() in (".yaml", ".yml")
)

failures = []
passes = []

def ok(msg: str) -> None:
    passes.append(msg)
    print(f"  [PASS] {msg}")

def err(msg: str) -> None:
    failures.append(msg)
    print(f"  [FAIL] {msg}")

if not yaml_files:
    err(f"No .yaml/.yml manifests found in {target_dir}")
    sys.exit(1)

docs = []
for path in yaml_files:
    try:
        loaded = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    except Exception as exc:
        err(f"{path.name}: failed to parse YAML ({exc})")
        continue
    for item in loaded:
        if item is not None:
            if not isinstance(item, dict):
                err(f"{path.name}: expected YAML mapping document")
            else:
                docs.append((path.name, item))

deployments = [d for _, d in docs if d.get("kind") == "Deployment"]
if deployments:
    names = ", ".join((d.get("metadata") or {}).get("name", "<unnamed>") for d in deployments)
    err(f"Found Deployment(s) [{names}]; convert Deployment to StatefulSet and remove Deployment manifests")
else:
    ok("No Deployment manifests remain")

statefulsets = [(fn, d) for fn, d in docs if d.get("kind") == "StatefulSet"]
services = [(fn, d) for fn, d in docs if d.get("kind") == "Service"]

sts = None
sts_file = None
for fn, d in statefulsets:
    meta = d.get("metadata") or {}
    if meta.get("name") == "booking-db":
        sts = d
        sts_file = fn
        break

if sts is None:
    err("Missing kind: StatefulSet with metadata.name: booking-db")
    sys.exit(1)

sts_meta = sts.get("metadata") or {}
sts_ns = sts_meta.get("namespace")
if sts_ns == "apollo-airlines-apps":
    ok(f"{sts_file}: StatefulSet booking-db is in namespace apollo-airlines-apps")
else:
    err(f"{sts_file}: StatefulSet namespace must be apollo-airlines-apps (got {sts_ns!r})")

sts_spec = sts.get("spec") or {}
service_name = sts_spec.get("serviceName")
if isinstance(service_name, str) and service_name.strip():
    ok(f"{sts_file}: StatefulSet defines spec.serviceName={service_name}")
else:
    err(f"{sts_file}: StatefulSet missing spec.serviceName")
    service_name = ""

replicas = sts_spec.get("replicas", 1)
if isinstance(replicas, int) and replicas >= 1:
    ok(f"{sts_file}: StatefulSet replicas={replicas}")
else:
    err(f"{sts_file}: StatefulSet replicas must be >= 1 (got {replicas!r})")

match_labels = ((sts_spec.get("selector") or {}).get("matchLabels")) or {}
template = sts_spec.get("template") or {}
pod_labels = ((template.get("metadata") or {}).get("labels")) or {}
if match_labels and all(pod_labels.get(k) == v for k, v in match_labels.items()):
    ok(f"{sts_file}: StatefulSet selector.matchLabels matches template.metadata.labels")
else:
    err(f"{sts_file}: StatefulSet selector.matchLabels {match_labels!r} does not match template labels {pod_labels!r}")

pod_spec = template.get("spec") or {}
containers = pod_spec.get("containers") or []
pg_container = next((c for c in containers if isinstance(c, dict)), None)
container_ports = set()
pg_mounts = {}
pgdata_val = None

if pg_container is None:
    err(f"{sts_file}: StatefulSet pod template has no containers")
else:
    for p in pg_container.get("ports") or []:
        if isinstance(p, dict) and p.get("containerPort") is not None:
            container_ports.add(p["containerPort"])
    if 5432 in container_ports:
        ok(f"{sts_file}: Postgres container exposes containerPort 5432")
    else:
        err(f"{sts_file}: Postgres container must expose containerPort 5432 (got {sorted(container_ports)})")

    for env_item in pg_container.get("env") or []:
        if isinstance(env_item, dict) and env_item.get("name") == "PGDATA":
            pgdata_val = env_item.get("value")
    if isinstance(pgdata_val, str) and pgdata_val.startswith("/var/lib/postgresql/data/"):
        ok(f"{sts_file}: PGDATA configured as subdirectory ({pgdata_val})")
    else:
        err(f"{sts_file}: PGDATA env should be set to /var/lib/postgresql/data/pgdata (got {pgdata_val!r})")

    for vm in pg_container.get("volumeMounts") or []:
        if isinstance(vm, dict) and vm.get("name"):
            pg_mounts[vm["name"]] = vm.get("mountPath")

    if pg_mounts.get("init-script") == "/docker-entrypoint-initdb.d":
        ok(f"{sts_file}: init-script mounted at /docker-entrypoint-initdb.d")
    else:
        err(f"{sts_file}: expected volumeMount init-script -> /docker-entrypoint-initdb.d")

volumes = pod_spec.get("volumes") or []
has_emptydir = any(isinstance(v, dict) and "emptyDir" in v for v in volumes)
if has_emptydir:
    err(f"{sts_file}: emptyDir volume still present; replace with volumeClaimTemplates")
else:
    ok(f"{sts_file}: no emptyDir volume present")

has_init_cm = any(
    isinstance(v, dict)
    and v.get("name") == "init-script"
    and (v.get("configMap") or {}).get("name") == "booking-db-init-script"
    for v in volumes
)
if has_init_cm:
    ok(f"{sts_file}: init-script ConfigMap volume references booking-db-init-script")
else:
    err(f"{sts_file}: expected volumes entry init-script referencing ConfigMap booking-db-init-script")

vcts = sts_spec.get("volumeClaimTemplates") or []
valid_vct = False
if not isinstance(vcts, list) or not vcts:
    err(f"{sts_file}: StatefulSet missing spec.volumeClaimTemplates")
else:
    for vct in vcts:
        if not isinstance(vct, dict):
            continue
        vct_name = (vct.get("metadata") or {}).get("name")
        vct_spec = vct.get("spec") or {}
        access_modes = vct_spec.get("accessModes") or []
        storage_req = ((vct_spec.get("resources") or {}).get("requests") or {}).get("storage")
        if (
            vct_name
            and pg_mounts.get(vct_name) == "/var/lib/postgresql/data"
            and "ReadWriteOnce" in access_modes
            and isinstance(storage_req, str)
            and storage_req.strip()
        ):
            valid_vct = True
            ok(f"{sts_file}: volumeClaimTemplate {vct_name!r} uses ReadWriteOnce ({storage_req}) mounted at /var/lib/postgresql/data")
            break
    if not valid_vct:
        err(f"{sts_file}: volumeClaimTemplates must include a ReadWriteOnce PVC with storage request mounted at /var/lib/postgresql/data")

headless_svc = None
headless_file = None
cluster_svc = None
cluster_file = None

for fn, svc in services:
    svc_meta = svc.get("metadata") or {}
    svc_spec = svc.get("spec") or {}
    name = svc_meta.get("name")
    cip = svc_spec.get("clusterIP")
    if name == service_name or cip == "None":
        headless_svc = svc
        headless_file = fn
    elif name == "booking-db":
        cluster_svc = svc
        cluster_file = fn

def check_service_common(fn: str, svc: dict, expected_name: str, expect_headless: bool) -> None:
    meta = svc.get("metadata") or {}
    spec = svc.get("spec") or {}
    name = meta.get("name")
    ns = meta.get("namespace")
    if name != expected_name:
        err(f"{fn}: expected Service name {expected_name!r}, got {name!r}")
    if ns != "apollo-airlines-apps":
        err(f"{fn}: Service {name} namespace must be apollo-airlines-apps (got {ns!r})")
    sel = spec.get("selector") or {}
    if not sel or not all(pod_labels.get(k) == v for k, v in sel.items()):
        err(f"{fn}: Service {name} selector {sel!r} does not match StatefulSet pod labels {pod_labels!r}")
    else:
        ok(f"{fn}: Service {name} selector matches StatefulSet pod labels")
    ports = spec.get("ports") or []
    port_ok = any(
        isinstance(p, dict) and p.get("port") == 5432 and p.get("targetPort") == 5432
        for p in ports
    )
    if port_ok:
        ok(f"{fn}: Service {name} maps port 5432 -> targetPort 5432")
    else:
        err(f"{fn}: Service {name} must expose port 5432 -> targetPort 5432")
    cip = spec.get("clusterIP")
    if expect_headless:
        if cip == "None":
            ok(f"{fn}: Headless Service {name} sets clusterIP: None")
        else:
            err(f"{fn}: Headless Service {name} must set clusterIP: None (got {cip!r})")
    else:
        svc_type = spec.get("type", "ClusterIP")
        if svc_type == "ClusterIP" and cip != "None":
            ok(f"{fn}: Regular Service {name} uses ClusterIP")
        else:
            err(f"{fn}: Regular Service {name} must be ClusterIP (got type={svc_type!r}, clusterIP={cip!r})")

if headless_svc is None:
    err(f"Missing headless Service (expected metadata.name: {service_name or 'booking-db-headless'} with clusterIP: None)")
else:
    check_service_common(headless_file, headless_svc, service_name or "booking-db-headless", expect_headless=True)

if cluster_svc is None:
    err("Missing regular ClusterIP Service named booking-db")
else:
    check_service_common(cluster_file, cluster_svc, "booking-db", expect_headless=False)

if failures:
    print(f"\nStage 3 check failed ({len(failures)} error(s)).")
    sys.exit(1)

print(f"\nStage 3 check passed ({len(passes)} check(s)).")
PY
