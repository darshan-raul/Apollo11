#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf 'Usage: %s [--solution | <manifest-dir>]\n' "$0"
  printf '  --solution      Validate the reference manifests in solution/\n'
  printf '  <manifest-dir>  Validate manifests in a specific directory (default: work/)\n'
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

if [[ "${USE_SOLUTION}" == true ]]; then
  if [[ -n "${TARGET_DIR}" ]]; then
    printf 'Cannot combine --solution with a directory argument.\n' >&2
    exit 2
  fi
  TARGET_DIR="${SCRIPT_DIR}/solution"
elif [[ -z "${TARGET_DIR}" ]]; then
  TARGET_DIR="${SCRIPT_DIR}/work"
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
  printf 'FAIL: directory not found: %s\n' "${TARGET_DIR}" >&2
  printf 'Hint: mkdir -p "%s/work" && cp "%s"/starter/*.yaml "%s/work/"\n' \
    "${SCRIPT_DIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'FAIL: python3 is required to validate Stage 1 manifests.\n' >&2
  exit 1
}

python3 - "${TARGET_DIR}" <<'PY'
import pathlib
import sys
import yaml

target_dir = pathlib.Path(sys.argv[1])
yaml_files = sorted(
    [p for p in target_dir.rglob("*") if p.is_file() and p.suffix.lower() in (".yaml", ".yml")]
)

errors = []
if not yaml_files:
    errors.append(f"No YAML files found in {target_dir}")

docs = []
for path in yaml_files:
    try:
        raw = path.read_text(encoding="utf-8")
        for doc in yaml.safe_load_all(raw):
            if isinstance(doc, dict):
                docs.append((path.name, doc))
    except Exception as exc:
        errors.append(f"{path.name}: failed to parse YAML: {exc}")


def find_placeholders(obj, loc=""):
    hits = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            hits.extend(find_placeholders(v, f"{loc}.{k}" if loc else str(k)))
    elif isinstance(obj, list):
        for idx, item in enumerate(obj):
            hits.extend(find_placeholders(item, f"{loc}[{idx}]"))
    elif isinstance(obj, str):
        upper = obj.upper()
        if "TODO" in upper or "CHANGE_ME" in upper:
            hits.append(f"{loc}={obj!r}")
    return hits


for fname, doc in docs:
    for hit in find_placeholders(doc):
        errors.append(f"{fname}: unresolved placeholder at {hit}")

cms = [(fn, d) for fn, d in docs if d.get("kind") == "ConfigMap"]
deps = [(fn, d) for fn, d in docs if d.get("kind") == "Deployment"]
svcs = [(fn, d) for fn, d in docs if d.get("kind") == "Service"]

if not cms:
    errors.append("Missing kind: ConfigMap manifest")
if not deps:
    errors.append("Missing kind: Deployment manifest")
if not svcs:
    errors.append("Missing kind: Service manifest")

cm_names = set()
if cms:
    cm_fn, cm = cms[0]
    if cm.get("apiVersion") != "v1":
        errors.append(f"{cm_fn}: ConfigMap apiVersion must be 'v1'")
    cm_meta = cm.get("metadata") or {}
    cm_name = cm_meta.get("name")
    if not cm_name:
        errors.append(f"{cm_fn}: ConfigMap metadata.name is required")
    else:
        cm_names.add(cm_name)
    if cm_meta.get("namespace") != "apollo-airlines":
        errors.append(f"{cm_fn}: ConfigMap metadata.namespace must be 'apollo-airlines'")
    cm_data = cm.get("data") or {}
    if not isinstance(cm_data, dict):
        errors.append(f"{cm_fn}: ConfigMap data must be a mapping")
        cm_data = {}
    expected_urls = {
        "FLIGHT_SERVICE_URL": "http://flight:8081",
        "IDENTITY_SERVICE_URL": "http://identity:8080",
        "NOTIFICATION_SERVICE_URL": "http://notification:8084",
    }
    for key, expected_val in expected_urls.items():
        if str(cm_data.get(key, "")) != expected_val:
            errors.append(f"{cm_fn}: ConfigMap data.{key} must be '{expected_val}'")
    port_val = str(cm_data.get("PORT", cm_data.get("PORT_BOOKING", "")))
    if port_val != "8082":
        errors.append(f"{cm_fn}: ConfigMap must define PORT: \"8082\" (or PORT_BOOKING: \"8082\")")

pod_labels = {}
if deps:
    dep_fn, dep = deps[0]
    if dep.get("apiVersion") != "apps/v1":
        errors.append(f"{dep_fn}: Deployment apiVersion must be 'apps/v1'")
    dep_meta = dep.get("metadata") or {}
    if dep_meta.get("name") != "booking":
        errors.append(f"{dep_fn}: Deployment metadata.name must be 'booking'")
    if dep_meta.get("namespace") != "apollo-airlines":
        errors.append(f"{dep_fn}: Deployment metadata.namespace must be 'apollo-airlines'")
    dep_spec = dep.get("spec") or {}
    replicas = dep_spec.get("replicas")
    if not isinstance(replicas, int) or replicas < 2:
        errors.append(f"{dep_fn}: Deployment spec.replicas must be >= 2 (got {replicas!r})")
    match_labels = (dep_spec.get("selector") or {}).get("matchLabels") or {}
    tpl = dep_spec.get("template") or {}
    pod_labels = (tpl.get("metadata") or {}).get("labels") or {}
    if not match_labels or match_labels.get("app") != "booking":
        errors.append(f"{dep_fn}: Deployment spec.selector.matchLabels must include app: booking")
    for k, v in match_labels.items():
        if pod_labels.get(k) != v:
            errors.append(f"{dep_fn}: Deployment template.metadata.labels[{k!r}] does not match selector.matchLabels")
    pod_spec = tpl.get("spec") or {}
    if pod_spec.get("serviceAccountName") != "booking":
        errors.append(f"{dep_fn}: Deployment template.spec.serviceAccountName must be 'booking'")
    containers = pod_spec.get("containers") or []
    booking_c = next((c for c in containers if isinstance(c, dict) and c.get("name") == "booking"), None)
    if booking_c is None:
        errors.append(f"{dep_fn}: Deployment must define a container named 'booking'")
    else:
        if booking_c.get("image") != "apollo11/booking:latest":
            errors.append(f"{dep_fn}: container image must be 'apollo11/booking:latest'")
        cports = [p.get("containerPort") for p in (booking_c.get("ports") or []) if isinstance(p, dict)]
        if 8082 not in cports:
            errors.append(f"{dep_fn}: container must expose containerPort 8082")
        referenced_cms = set()
        for ef in booking_c.get("envFrom") or []:
            if isinstance(ef, dict):
                cm_ref = (ef.get("configMapRef") or {}).get("name")
                if cm_ref:
                    referenced_cms.add(cm_ref)
        for ev in booking_c.get("env") or []:
            if isinstance(ev, dict):
                cm_key_ref = ((ev.get("valueFrom") or {}).get("configMapKeyRef") or {}).get("name")
                if cm_key_ref:
                    referenced_cms.add(cm_key_ref)
        if not (referenced_cms & cm_names):
            errors.append(
                f"{dep_fn}: booking container must reference ConfigMap {sorted(cm_names) or ['booking-config']} via envFrom or env"
            )
        liveness = booking_c.get("livenessProbe") or {}
        l_http = liveness.get("httpGet") or {}
        if l_http.get("path") != "/healthz" or l_http.get("port") != 8082:
            errors.append(f"{dep_fn}: livenessProbe must target HTTP /healthz on port 8082")
        readiness = booking_c.get("readinessProbe") or {}
        r_http = readiness.get("httpGet") or {}
        if r_http.get("path") != "/readyz" or r_http.get("port") != 8082:
            errors.append(f"{dep_fn}: readinessProbe must target HTTP /readyz on port 8082")

if svcs:
    svc_fn, svc = svcs[0]
    if svc.get("apiVersion") != "v1":
        errors.append(f"{svc_fn}: Service apiVersion must be 'v1'")
    svc_meta = svc.get("metadata") or {}
    if svc_meta.get("name") != "booking":
        errors.append(f"{svc_fn}: Service metadata.name must be 'booking'")
    if svc_meta.get("namespace") != "apollo-airlines":
        errors.append(f"{svc_fn}: Service metadata.namespace must be 'apollo-airlines'")
    svc_spec = svc.get("spec") or {}
    svc_type = svc_spec.get("type", "ClusterIP")
    if svc_type != "ClusterIP":
        errors.append(f"{svc_fn}: Service spec.type must be 'ClusterIP' (got {svc_type!r})")
    svc_sel = svc_spec.get("selector") or {}
    if not svc_sel or svc_sel.get("app") != "booking":
        errors.append(f"{svc_fn}: Service spec.selector must include app: booking")
    for k, v in svc_sel.items():
        if pod_labels and pod_labels.get(k) != v:
            errors.append(f"{svc_fn}: Service selector[{k!r}]={v!r} does not match Deployment Pod label")
    ports = svc_spec.get("ports") or []
    matching_port = False
    for p in ports:
        if not isinstance(p, dict):
            continue
        if p.get("nodePort") is not None:
            errors.append(f"{svc_fn}: Service must not define nodePort in Stage 1")
        if p.get("port") == 8082 and p.get("targetPort") == 8082:
            matching_port = True
    if not matching_port:
        errors.append(f"{svc_fn}: Service must expose port 8082 -> targetPort 8082")

if errors:
    for err in errors:
        print(f"FAIL: {err}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: Stage 1 booking manifests validated in {target_dir}")
PY
