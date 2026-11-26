#!/usr/bin/env bash
# Offline verification for Stage 5 Author-Before-Bootstrap (Helm + Kustomize).
#
# Usage:
#   bash learner-work/stage5/check.sh              # check work/ (initializes from starter/ if absent)
#   bash learner-work/stage5/check.sh --solution   # verify reference solution/
#   bash learner-work/stage5/check.sh starter      # verify a specific directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--solution | --starter | <dir>]

Options:
  --solution    Check $SCRIPT_DIR/solution
  --starter     Check $SCRIPT_DIR/starter
  --help, -h    Show this help
  <dir>         Check the specified exercise directory (default: work/, copied from starter/ if absent)
EOF
}

TARGET_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --solution) TARGET_ARG="$SCRIPT_DIR/solution"; shift ;;
    --starter)  TARGET_ARG="$SCRIPT_DIR/starter"; shift ;;
    --help|-h)  usage; exit 0 ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$TARGET_ARG" ]]; then
        echo "ERROR: unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      TARGET_ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_ARG" ]]; then
  TARGET_DIR="$SCRIPT_DIR/work"
  if [[ ! -d "$TARGET_DIR" ]]; then
    cp -R "$SCRIPT_DIR/starter" "$TARGET_DIR"
    echo "Initialized $TARGET_DIR from starter/."
  fi
elif [[ -d "$TARGET_ARG" ]]; then
  TARGET_DIR="$(cd "$TARGET_ARG" && pwd)"
elif [[ -d "$SCRIPT_DIR/$TARGET_ARG" ]]; then
  TARGET_DIR="$(cd "$SCRIPT_DIR/$TARGET_ARG" && pwd)"
else
  echo "ERROR: target directory not found: $TARGET_ARG" >&2
  exit 2
fi

for cmd in helm kubectl python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool '$cmd' not found on PATH" >&2
    exit 127
  fi
done

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

CHART_DIR="$TARGET_DIR/chart"
KUST_BASE="$TARGET_DIR/kustomize/base"
KUST_PROD="$TARGET_DIR/kustomize/overlays/prod"

echo "== Checking Stage 5 exercise in: $TARGET_DIR =="

# 1. Chart structure + helm lint
if [[ -f "$CHART_DIR/Chart.yaml" && -f "$CHART_DIR/values.yaml" && -f "$CHART_DIR/values.schema.json" ]]; then
  if helm lint "$CHART_DIR" >/dev/null 2>&1; then
    pass "helm lint passed"
  else
    fail "helm lint failed on $CHART_DIR"
  fi
else
  fail "missing required Helm chart files under $CHART_DIR"
fi

# 2. New chart value + _helpers.tpl helper + template wiring
if python3 - "$CHART_DIR/values.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
val = ((data.get("apps") or {}).get("booking") or {}).get("releaseChannel")
sys.exit(0 if val in ("canary", "stable", "lts") else 1)
PY
then
  pass "values.yaml defines apps.booking.releaseChannel (valid default)"
else
  fail "values.yaml missing valid apps.booking.releaseChannel (expected canary, stable, or lts)"
fi

if [[ -f "$CHART_DIR/templates/_helpers.tpl" ]] && grep -q 'define "apollo11.releaseAnnotations"' "$CHART_DIR/templates/_helpers.tpl"; then
  pass "templates/_helpers.tpl defines apollo11.releaseAnnotations"
else
  fail "templates/_helpers.tpl missing helper definition apollo11.releaseAnnotations"
fi

if [[ -f "$CHART_DIR/templates/booking.yaml" ]] && grep -q 'include "apollo11.releaseAnnotations"' "$CHART_DIR/templates/booking.yaml"; then
  pass "templates/booking.yaml includes apollo11.releaseAnnotations"
else
  fail "templates/booking.yaml does not include apollo11.releaseAnnotations"
fi

# 3. Helm template rendering (default + --set override)
if default_render=$(helm template apollo11 "$CHART_DIR" 2>&1); then
  if python3 - "$default_render" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.argv[1]) if isinstance(d, dict)]
dep = next((d for d in docs if d.get("kind") == "Deployment" and (d.get("metadata") or {}).get("name") == "booking"), None)
if not dep:
    sys.exit(1)
ann = (((dep.get("spec") or {}).get("template") or {}).get("metadata") or {}).get("annotations") or {}
sys.exit(0 if ann.get("apollo.airlines/release-channel") in ("canary", "stable", "lts") else 1)
PY
  then
    pass "helm template renders Deployment/booking with apollo.airlines/release-channel annotation"
  else
    fail "helm template Deployment/booking missing apollo.airlines/release-channel annotation"
  fi
else
  fail "helm template failed: $default_render"
fi

if override_render=$(helm template apollo11 "$CHART_DIR" --set apps.booking.releaseChannel=canary 2>&1); then
  if python3 - "$override_render" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.argv[1]) if isinstance(d, dict)]
dep = next((d for d in docs if d.get("kind") == "Deployment" and (d.get("metadata") or {}).get("name") == "booking"), None)
if not dep:
    sys.exit(1)
ann = (((dep.get("spec") or {}).get("template") or {}).get("metadata") or {}).get("annotations") or {}
sys.exit(0 if ann.get("apollo.airlines/release-channel") == "canary" else 1)
PY
  then
    pass "helm template --set apps.booking.releaseChannel=canary propagates through helper"
  else
    fail "helm template --set apps.booking.releaseChannel=canary did not update annotation to 'canary'"
  fi
else
  fail "helm template --set apps.booking.releaseChannel=canary failed"
fi

# 4. values.schema.json validation (must reject invalid enum value)
if python3 - "$CHART_DIR/values.schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1], encoding="utf-8"))
app = (schema.get("definitions") or {}).get("app") or {}
rc = (app.get("properties") or {}).get("releaseChannel") or {}
req = app.get("required") or []
ok = ("releaseChannel" in req) and (rc.get("type") == "string") and set(rc.get("enum") or []) == {"canary", "stable", "lts"}
sys.exit(0 if ok else 1)
PY
then
  pass "values.schema.json defines required enum constraint on releaseChannel"
else
  fail "values.schema.json missing required/enum constraint on definitions.app.properties.releaseChannel"
fi

if helm template apollo11 "$CHART_DIR" --set apps.booking.releaseChannel=invalid-channel >/dev/null 2>&1; then
  fail "values.schema.json did NOT reject invalid apps.booking.releaseChannel=invalid-channel"
else
  pass "helm template rejects invalid apps.booking.releaseChannel=invalid-channel via values.schema.json"
fi

# 5. Kustomize overlay patch verification
if [[ -f "$KUST_BASE/kustomization.yaml" && -f "$KUST_PROD/kustomization.yaml" ]]; then
  if python3 - "$KUST_PROD/kustomization.yaml" <<'PY'
import sys, yaml
k = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
patches = k.get("patches") or []
sys.exit(0 if isinstance(patches, list) and len(patches) > 0 else 1)
PY
  then
    pass "kustomize/overlays/prod/kustomization.yaml declares patches"
  else
    fail "kustomize/overlays/prod/kustomization.yaml missing patches entry"
  fi

  if base_render=$(kubectl kustomize "$KUST_BASE" 2>&1) && prod_render=$(kubectl kustomize "$KUST_PROD" 2>&1); then
    if python3 - "$base_render" "$prod_render" <<'PY'
import sys, yaml
def find_booking(stream):
    docs = [d for d in yaml.safe_load_all(stream) if isinstance(d, dict)]
    return next((d for d in docs if d.get("kind") == "Deployment" and (d.get("metadata") or {}).get("name") == "booking"), None)

b_dep = find_booking(sys.argv[1])
p_dep = find_booking(sys.argv[2])
if not b_dep or not p_dep:
    sys.exit(1)
b_ann = (((b_dep.get("spec") or {}).get("template") or {}).get("metadata") or {}).get("annotations") or {}
p_ann = (((p_dep.get("spec") or {}).get("template") or {}).get("metadata") or {}).get("annotations") or {}
p_labels = (p_dep.get("metadata") or {}).get("labels") or {}
p_reps = (p_dep.get("spec") or {}).get("replicas")
ok = (
    b_ann.get("apollo.airlines/release-channel") == "stable"
    and p_ann.get("apollo.airlines/release-channel") == "lts"
    and p_labels.get("environment") == "prod"
    and p_reps == 3
)
sys.exit(0 if ok else 1)
PY
    then
      pass "kubectl kustomize prod overlay patches Deployment/booking release-channel to lts (base=stable, replicas=3)"
    else
      fail "kubectl kustomize prod overlay did not render expected Deployment/booking patch (release-channel=lts, replicas=3, environment=prod)"
    fi
  else
    fail "kubectl kustomize failed on base or prod overlay"
  fi
else
  fail "missing Kustomize base or prod overlay files under $TARGET_DIR/kustomize"
fi

printf '\nStage 5 exercise check: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
