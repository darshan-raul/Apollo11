#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""
USE_SOLUTION=false

usage() {
  printf 'Usage: %s [--solution | <manifest-dir>]\n' "$0"
  printf '  --solution      Validate the reference manifests in solution/\n'
  printf '  <manifest-dir>  Validate manifests in a specific directory (default: work/)\n'
}

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
  printf 'FAIL: python3 is required to validate Stage 6 observability files.\n' >&2
  exit 1
}

resolve_promtool() {
  local cand
  if command -v promtool >/dev/null 2>&1; then
    cand="$(command -v promtool)"
    if "${cand}" --version >/dev/null 2>&1; then
      printf '%s\n' "${cand}"
      return 0
    fi
  fi
  if [[ -x "${HOME}/.local/share/mise/shims/promtool" ]] && "${HOME}/.local/share/mise/shims/promtool" --version >/dev/null 2>&1; then
    printf '%s\n' "${HOME}/.local/share/mise/shims/promtool"
    return 0
  fi
  if [[ -d "${HOME}/.local/share/mise/installs/promtool" ]]; then
    while IFS= read -r cand; do
      if [[ -x "${cand}" ]] && "${cand}" --version >/dev/null 2>&1; then
        printf '%s\n' "${cand}"
        return 0
      fi
    done < <(find "${HOME}/.local/share/mise/installs/promtool" -type f -name promtool 2>/dev/null | sort -r)
  fi
  return 1
}

PROMTOOL_BIN="$(resolve_promtool || true)"
if [[ -z "${PROMTOOL_BIN}" ]]; then
  printf 'FAIL: promtool is required to execute rules_test.yaml.\n' >&2
  exit 1
fi

TMP_WORK="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_WORK}"
}
trap cleanup EXIT

python3 - "${TARGET_DIR}" "${TMP_WORK}" <<'PY'
import pathlib
import sys
import yaml

target_dir = pathlib.Path(sys.argv[1])
tmp_work = pathlib.Path(sys.argv[2])

yaml_files = sorted(
    [p for p in target_dir.rglob("*") if p.is_file() and p.suffix.lower() in (".yaml", ".yml")]
)

errors = []
if not yaml_files:
    errors.append(f"No YAML files found in {target_dir}")

docs = []
test_docs = []

for path in yaml_files:
    try:
        raw = path.read_text(encoding="utf-8")
        for doc in yaml.safe_load_all(raw):
            if isinstance(doc, dict):
                if "tests" in doc and "rule_files" in doc:
                    test_docs.append((path.name, doc))
                else:
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


for fname, doc in docs + test_docs:
    for hit in find_placeholders(doc):
        errors.append(f"{fname}: unresolved placeholder at {hit}")

sms = [(fn, d) for fn, d in docs if d.get("kind") == "ServiceMonitor"]
prs = [(fn, d) for fn, d in docs if d.get("kind") == "PrometheusRule"]

if not sms:
    errors.append("Missing kind: ServiceMonitor manifest")
if not prs:
    errors.append("Missing kind: PrometheusRule manifest")
if not test_docs:
    errors.append("Missing promtool test rules file (must define rule_files and tests)")

if sms:
    sm_fn, sm = sms[0]
    if sm.get("apiVersion") != "monitoring.coreos.com/v1":
        errors.append(f"{sm_fn}: ServiceMonitor apiVersion must be 'monitoring.coreos.com/v1'")
    sm_meta = sm.get("metadata") or {}
    if not sm_meta.get("name"):
        errors.append(f"{sm_fn}: ServiceMonitor metadata.name is required")
    if sm_meta.get("namespace") != "apollo-observability":
        errors.append(f"{sm_fn}: ServiceMonitor metadata.namespace must be 'apollo-observability'")
    sm_labels = sm_meta.get("labels") or {}
    if sm_labels.get("app.kubernetes.io/part-of") != "apollo-airlines":
        errors.append(
            f"{sm_fn}: ServiceMonitor metadata.labels['app.kubernetes.io/part-of'] must be 'apollo-airlines'"
        )
    sm_spec = sm.get("spec") or {}
    sel_labels = (sm_spec.get("selector") or {}).get("matchLabels") or {}
    if sel_labels.get("app") != "flight":
        errors.append(f"{sm_fn}: ServiceMonitor spec.selector.matchLabels.app must be 'flight'")
    ns_sel = sm_spec.get("namespaceSelector") or {}
    match_names = ns_sel.get("matchNames") or []
    if not (ns_sel.get("any") is True or (isinstance(match_names, list) and "apollo-airlines-apps" in match_names)):
        errors.append(
            f"{sm_fn}: ServiceMonitor spec.namespaceSelector must allow 'apollo-airlines-apps' (matchNames or any: true)"
        )
    endpoints = sm_spec.get("endpoints") or []
    if not isinstance(endpoints, list) or not endpoints or not isinstance(endpoints[0], dict):
        errors.append(f"{sm_fn}: ServiceMonitor spec.endpoints must contain at least one endpoint")
    else:
        ep0 = endpoints[0]
        if ep0.get("port") != "http":
            errors.append(f"{sm_fn}: ServiceMonitor spec.endpoints[0].port must be 'http'")
        if ep0.get("path") != "/metrics":
            errors.append(f"{sm_fn}: ServiceMonitor spec.endpoints[0].path must be '/metrics'")

if prs:
    pr_fn, pr = prs[0]
    if pr.get("apiVersion") != "monitoring.coreos.com/v1":
        errors.append(f"{pr_fn}: PrometheusRule apiVersion must be 'monitoring.coreos.com/v1'")
    pr_meta = pr.get("metadata") or {}
    if not pr_meta.get("name"):
        errors.append(f"{pr_fn}: PrometheusRule metadata.name is required")
    if pr_meta.get("namespace") != "apollo-observability":
        errors.append(f"{pr_fn}: PrometheusRule metadata.namespace must be 'apollo-observability'")
    pr_labels = pr_meta.get("labels") or {}
    if pr_labels.get("app.kubernetes.io/part-of") != "apollo-airlines":
        errors.append(
            f"{pr_fn}: PrometheusRule metadata.labels['app.kubernetes.io/part-of'] must be 'apollo-airlines'"
        )
    pr_spec = pr.get("spec") or {}
    groups = pr_spec.get("groups") or []
    if not isinstance(groups, list) or not groups:
        errors.append(f"{pr_fn}: PrometheusRule spec.groups must be non-empty")
    else:
        all_rules = [
            r
            for g in groups
            if isinstance(g, dict)
            for r in (g.get("rules") or [])
            if isinstance(r, dict)
        ]
        rec_rules = [r for r in all_rules if r.get("record")]
        alert_rules = [r for r in all_rules if r.get("alert")]
        if not rec_rules:
            errors.append(f"{pr_fn}: PrometheusRule must define at least one recording rule")
        if not alert_rules:
            errors.append(f"{pr_fn}: PrometheusRule must define at least one alert rule")
        all_exprs = "\n".join(str(r.get("expr", "")) for r in all_rules)
        if "http_requests_total" not in all_exprs:
            errors.append(f"{pr_fn}: rules must reference Stage 6 metric 'http_requests_total'")
        if "http_request_duration_ms_bucket" not in all_exprs or "histogram_quantile" not in all_exprs:
            errors.append(
                f"{pr_fn}: rules must include a histogram_quantile expression on 'http_request_duration_ms_bucket'"
            )
        (tmp_work / "rules.yaml").write_text(
            yaml.safe_dump({"groups": groups}, sort_keys=False),
            encoding="utf-8",
        )

if test_docs:
    td_fn, td = test_docs[0]
    if td.get("rule_files") != ["rules.yaml"]:
        errors.append(f"{td_fn}: rule_files must be ['rules.yaml']")
    tests = td.get("tests") or []
    if not isinstance(tests, list) or not tests:
        errors.append(f"{td_fn}: tests list must be non-empty")
    else:
        has_promql = any(isinstance(t, dict) and t.get("promql_expr_test") for t in tests)
        has_alert = any(isinstance(t, dict) and t.get("alert_rule_test") for t in tests)
        if not has_promql:
            errors.append(f"{td_fn}: tests must include at least one promql_expr_test")
        if not has_alert:
            errors.append(f"{td_fn}: tests must include at least one alert_rule_test")
    (tmp_work / "rules_test.yaml").write_text(
        yaml.safe_dump(td, sort_keys=False),
        encoding="utf-8",
    )

if errors:
    for err in errors:
        print(f"FAIL: {err}", file=sys.stderr)
    sys.exit(1)
PY

if ! promtool_out="$("${PROMTOOL_BIN}" test rules "${TMP_WORK}/rules_test.yaml" 2>&1)"; then
  printf '%s\n' "${promtool_out}" >&2
  exit 1
fi
printf 'PASS: Stage 6 ServiceMonitor, PrometheusRule, and promtool test rules verified in %s\n' "${TARGET_DIR}"
