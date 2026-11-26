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
  printf 'FAIL: python3 is required to validate Stage 7 manifests.\n' >&2
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


def is_real_int(val):
    return isinstance(val, int) and not isinstance(val, bool)


for fname, doc in docs:
    for hit in find_placeholders(doc):
        errors.append(f"{fname}: unresolved placeholder at {hit}")

hpas = [(fn, d) for fn, d in docs if d.get("kind") == "HorizontalPodAutoscaler"]
if not hpas:
    errors.append("Missing kind: HorizontalPodAutoscaler manifest")

if hpas:
    hpa_fn, hpa = hpas[0]
    if hpa.get("apiVersion") != "autoscaling/v2":
        errors.append(f"{hpa_fn}: HorizontalPodAutoscaler apiVersion must be 'autoscaling/v2'")

    meta = hpa.get("metadata") or {}
    if not isinstance(meta, dict):
        meta = {}
    if meta.get("name") != "search-hpa":
        errors.append(f"{hpa_fn}: metadata.name must be 'search-hpa'")
    if meta.get("namespace") != "apollo-airlines-apps":
        errors.append(f"{hpa_fn}: metadata.namespace must be 'apollo-airlines-apps'")

    spec = hpa.get("spec") or {}
    if not isinstance(spec, dict):
        spec = {}

    target_ref = spec.get("scaleTargetRef") or {}
    if not isinstance(target_ref, dict):
        target_ref = {}
    expected_ref = {"apiVersion": "apps/v1", "kind": "Deployment", "name": "search"}
    for key, val in expected_ref.items():
        if target_ref.get(key) != val:
            errors.append(f"{hpa_fn}: spec.scaleTargetRef.{key} must be {val!r}")

    min_rep = spec.get("minReplicas")
    max_rep = spec.get("maxReplicas")
    if not is_real_int(min_rep) or not (1 <= min_rep <= 3):
        errors.append(f"{hpa_fn}: spec.minReplicas must be an integer between 1 and 3 (got {min_rep!r})")
    if not is_real_int(max_rep) or max_rep < 3:
        errors.append(f"{hpa_fn}: spec.maxReplicas must be an integer >= 3 (got {max_rep!r})")
    if is_real_int(min_rep) and is_real_int(max_rep) and max_rep <= min_rep:
        errors.append(f"{hpa_fn}: spec.maxReplicas ({max_rep}) must be > spec.minReplicas ({min_rep})")

    metrics = spec.get("metrics") or []
    cpu_metric_ok = False
    if isinstance(metrics, list):
        for entry in metrics:
            if not isinstance(entry, dict):
                continue
            if entry.get("type") != "Resource":
                continue
            res = entry.get("resource") or {}
            if not isinstance(res, dict) or res.get("name") != "cpu":
                continue
            tgt = res.get("target") or {}
            if not isinstance(tgt, dict) or tgt.get("type") != "Utilization":
                continue
            avg_util = tgt.get("averageUtilization")
            if is_real_int(avg_util) and 1 <= avg_util <= 100:
                cpu_metric_ok = True
                break
    if not cpu_metric_ok:
        errors.append(
            f"{hpa_fn}: spec.metrics must define a Resource 'cpu' metric with target.type='Utilization' and 1 <= averageUtilization <= 100"
        )

    behavior = spec.get("behavior") or {}
    if not isinstance(behavior, dict):
        behavior = {}
    scale_down = behavior.get("scaleDown") or {}
    if not isinstance(scale_down, dict):
        scale_down = {}
    stab = scale_down.get("stabilizationWindowSeconds")
    if not is_real_int(stab) or stab < 60:
        errors.append(
            f"{hpa_fn}: spec.behavior.scaleDown.stabilizationWindowSeconds must be an integer >= 60 (got {stab!r})"
        )

    scale_up = behavior.get("scaleUp") or {}
    if not isinstance(scale_up, dict):
        scale_up = {}
    up_policies = scale_up.get("policies")
    if not isinstance(up_policies, list) or len(up_policies) == 0:
        errors.append(f"{hpa_fn}: spec.behavior.scaleUp.policies must be a non-empty list")

if errors:
    for err in errors:
        print(f"FAIL: {err}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: Stage 7 search-hpa manifest validated in {target_dir}")
PY
