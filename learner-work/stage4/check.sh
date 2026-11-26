#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""

usage() {
  echo "Usage: $0 [--solution | <dir>]"
  echo "  (no args)    Validate ${SCRIPT_DIR}/work"
  echo "  --solution   Validate ${SCRIPT_DIR}/solution"
  echo "  <dir>        Validate manifests inside <dir>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --solution)
      TARGET_DIR="${SCRIPT_DIR}/solution"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$TARGET_DIR" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-${SCRIPT_DIR}/work}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "FAIL: target directory not found: $TARGET_DIR" >&2
  echo "Hint: copy starter/ to work/ first: cp -r '${SCRIPT_DIR}/starter' '${SCRIPT_DIR}/work'" >&2
  exit 1
fi

python3 - "$TARGET_DIR" <<'PYEOF'
import pathlib
import re
import sys
import yaml

target = pathlib.Path(sys.argv[1])
yaml_files = sorted([*target.rglob("*.yaml"), *target.rglob("*.yml")])
if not yaml_files:
    print(f"FAIL: no YAML files found in {target}")
    sys.exit(1)

docs = []
errors = []

for yf in yaml_files:
    try:
        loaded = list(yaml.safe_load_all(yf.read_text(encoding="utf-8")))
    except Exception as exc:
        errors.append(f"{yf.name}: YAML parse error: {exc}")
        continue
    for d in loaded:
        if isinstance(d, dict):
            docs.append((yf.name, d))


def parse_cpu_millicores(val) -> float | None:
    s = str(val).strip()
    if s.endswith("m"):
        return float(s[:-1])
    if re.fullmatch(r"[0-9]+(\.[0-9]+)?", s):
        return float(s) * 1000.0
    return None


def parse_mem_bytes(val) -> float | None:
    s = str(val).strip()
    units = {
        "Ki": 1024,
        "Mi": 1024**2,
        "Gi": 1024**3,
        "Ti": 1024**4,
        "K": 1000,
        "M": 1000**2,
        "G": 1000**3,
        "T": 1000**4,
    }
    for suffix, mult in units.items():
        if s.endswith(suffix):
            num = s[: -len(suffix)]
            if re.fullmatch(r"[0-9]+(\.[0-9]+)?", num):
                return float(num) * mult
            return None
    if re.fullmatch(r"[0-9]+(\.[0-9]+)?", s):
        return float(s)
    return None


booking_dep = None
pdb_doc = None
for fname, doc in docs:
    kind = doc.get("kind")
    meta = doc.get("metadata") or {}
    name = meta.get("name")
    if kind == "Deployment" and name == "booking":
        booking_dep = (fname, doc)
    elif kind == "PodDisruptionBudget":
        pdb_doc = (fname, doc)

if booking_dep is None:
    errors.append("missing Deployment named 'booking'")
else:
    fname, dep = booking_dep
    spec = dep.get("spec") or {}
    tpl = spec.get("template") or {}
    pod_labels = (tpl.get("metadata") or {}).get("labels") or {}
    pod_spec = tpl.get("spec") or {}
    containers = pod_spec.get("containers") or []
    init_containers = pod_spec.get("initContainers") or []

    if pod_labels.get("app") != "booking":
        errors.append(f"{fname}: Deployment template labels must include app: booking")

    grace = pod_spec.get("terminationGracePeriodSeconds")
    if not isinstance(grace, int) or grace < 15:
        errors.append(f"{fname}: terminationGracePeriodSeconds must be >= 15 (found {grace!r})")

    booking_c = next((c for c in containers if isinstance(c, dict) and c.get("name") == "booking"), None)
    if booking_c is None:
        errors.append(f"{fname}: missing container named 'booking'")
    else:
        expected_probes = {
            "startupProbe": "/healthz/startup",
            "livenessProbe": "/healthz/live",
            "readinessProbe": "/healthz/ready",
        }
        for probe_name, expected_path in expected_probes.items():
            probe = booking_c.get(probe_name) or {}
            http_get = probe.get("httpGet") or {}
            path = http_get.get("path")
            port = http_get.get("port")
            if path != expected_path:
                errors.append(f"{fname}: {probe_name}.httpGet.path is {path!r}, expected {expected_path!r}")
            if port not in (8082, "8082"):
                errors.append(f"{fname}: {probe_name}.httpGet.port is {port!r}, expected 8082")

        prestop = ((booking_c.get("lifecycle") or {}).get("preStop") or {}).get("exec") or {}
        cmd = prestop.get("command") or []
        if not isinstance(cmd, list) or not cmd:
            errors.append(f"{fname}: container 'booking' missing lifecycle.preStop.exec.command")

    # Guaranteed QoS requires requests == limits for CPU and memory on EVERY container
    all_containers = [c for c in [*containers, *init_containers] if isinstance(c, dict)]
    if not all_containers:
        errors.append(f"{fname}: no containers defined")
    for c in all_containers:
        cname = c.get("name", "<unnamed>")
        res = c.get("resources") or {}
        req = res.get("requests") or {}
        lim = res.get("limits") or {}
        req_cpu = parse_cpu_millicores(req.get("cpu")) if req.get("cpu") is not None else None
        lim_cpu = parse_cpu_millicores(lim.get("cpu")) if lim.get("cpu") is not None else None
        req_mem = parse_mem_bytes(req.get("memory")) if req.get("memory") is not None else None
        lim_mem = parse_mem_bytes(lim.get("memory")) if lim.get("memory") is not None else None
        if req_cpu is None or lim_cpu is None or req_cpu <= 0 or req_cpu != lim_cpu:
            errors.append(
                f"{fname}: container '{cname}' fails Guaranteed CPU QoS "
                f"(requests.cpu={req.get('cpu')!r}, limits.cpu={lim.get('cpu')!r})"
            )
        if req_mem is None or lim_mem is None or req_mem <= 0 or req_mem != lim_mem:
            errors.append(
                f"{fname}: container '{cname}' fails Guaranteed memory QoS "
                f"(requests.memory={req.get('memory')!r}, limits.memory={lim.get('memory')!r})"
            )

if pdb_doc is None:
    errors.append("missing PodDisruptionBudget manifest for booking")
else:
    pfname, pdb = pdb_doc
    if pdb.get("apiVersion") != "policy/v1":
        errors.append(f"{pfname}: PodDisruptionBudget apiVersion must be 'policy/v1'")
    pspec = pdb.get("spec") or {}
    min_av = pspec.get("minAvailable")
    max_un = pspec.get("maxUnavailable")
    if min_av is None and max_un is None:
        errors.append(f"{pfname}: PodDisruptionBudget must set minAvailable or maxUnavailable")
    sel = ((pspec.get("selector") or {}).get("matchLabels")) or {}
    if not sel:
        errors.append(f"{pfname}: PodDisruptionBudget spec.selector.matchLabels must be non-empty")
    elif booking_dep is not None:
        pod_labels = ((booking_dep[1].get("spec") or {}).get("template") or {}).get("metadata", {}).get("labels") or {}
        for k, v in sel.items():
            if pod_labels.get(k) != v:
                errors.append(
                    f"{pfname}: PDB selector {k}={v!r} does not match booking pod template label {pod_labels.get(k)!r}"
                )

if errors:
    print("FAIL:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print(f"PASS: Stage 4 booking probes, Guaranteed QoS, preStop hook, and PodDisruptionBudget verified in {target}")
PYEOF
