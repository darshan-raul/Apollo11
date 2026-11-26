#!/usr/bin/env bash
# Shared helpers for Apollo11 E2E test runners (test/e2e/run_static_e2e.sh, run_live_e2e.sh).
# shellcheck shell=bash
set -euo pipefail

ensure_mise_path() {
  local mise_data="${MISE_DATA_DIR:-${HOME}/.local/share/mise}"
  local mise_shims="${mise_data}/shims"
  local local_bin="${HOME}/.local/bin"
  if [[ -d "$local_bin" ]] && [[ ":${PATH}:" != *":${local_bin}:"* ]]; then
    PATH="${local_bin}:${PATH}"
  fi
  if [[ -d "$mise_shims" ]] && [[ ":${PATH}:" != *":${mise_shims}:"* ]]; then
    PATH="${mise_shims}:${PATH}"
  fi
  export PATH
}

ensure_mise_path

# Counters shared across sourcing scripts
E2E_PASSED=0
E2E_FAILED=0
E2E_SKIPPED=0
E2E_WARNED=0
E2E_VERBOSE="${E2E_VERBOSE:-false}"
E2E_RESULTS_JSONL="${E2E_RESULTS_JSONL:-}"

_e2e_color() {
  local code="$1"
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    printf '\033[%sm' "$code"
  fi
}

_e2e_reset() {
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    printf '\033[0m'
  fi
}

log_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

step() {
  local msg="$1"
  printf '\n%s==> %s%s\n' "$(_e2e_color '1;34')" "$msg" "$(_e2e_reset)"
}

info() {
  local msg="$1"
  printf '%s[INFO]%s %s\n' "$(_e2e_color '0;36')" "$(_e2e_reset)" "$msg"
}

warn() {
  local msg="$1"
  E2E_WARNED=$((E2E_WARNED + 1))
  printf '%s[WARN]%s %s\n' "$(_e2e_color '1;33')" "$(_e2e_reset)" "$msg" >&2
}

pass() {
  local label="$1"
  local detail="${2:-}"
  E2E_PASSED=$((E2E_PASSED + 1))
  if [[ -n "$detail" ]]; then
    printf '%s[PASS]%s %s — %s\n' "$(_e2e_color '0;32')" "$(_e2e_reset)" "$label" "$detail"
  else
    printf '%s[PASS]%s %s\n' "$(_e2e_color '0;32')" "$(_e2e_reset)" "$label"
  fi
}

fail() {
  local label="$1"
  local detail="${2:-}"
  E2E_FAILED=$((E2E_FAILED + 1))
  if [[ -n "$detail" ]]; then
    printf '%s[FAIL]%s %s — %s\n' "$(_e2e_color '0;31')" "$(_e2e_reset)" "$label" "$detail" >&2
  else
    printf '%s[FAIL]%s %s\n' "$(_e2e_color '0;31')" "$(_e2e_reset)" "$label" >&2
  fi
}

skip() {
  local label="$1"
  local detail="${2:-}"
  E2E_SKIPPED=$((E2E_SKIPPED + 1))
  if [[ -n "$detail" ]]; then
    printf '%s[SKIP]%s %s — %s\n' "$(_e2e_color '0;33')" "$(_e2e_reset)" "$label" "$detail"
  else
    printf '%s[SKIP]%s %s\n' "$(_e2e_color '0;33')" "$(_e2e_reset)" "$label"
  fi
}

record_check() {
  local id="$1"
  local tier="$2"
  local status="$3"
  local summary="$4"
  local detail="${5:-}"

  case "$status" in
    PASS)
      pass "$id" "$summary"
      if [[ "$E2E_VERBOSE" == "true" ]] && [[ -n "$detail" ]]; then
        printf '       %s\n' "${detail//$'\n'/$'\n       '}"
      fi
      ;;
    FAIL)
      fail "$id" "$summary"
      if [[ -n "$detail" ]]; then
        printf '       %s\n' "${detail//$'\n'/$'\n       '}" >&2
      fi
      ;;
    SKIP)
      skip "$id" "$summary"
      if [[ -n "$detail" ]]; then
        printf '       %s\n' "${detail//$'\n'/$'\n       '}" >&2
      fi
      ;;
    *)
      fail "$id" "Unknown check status '$status': $summary"
      status="FAIL"
      ;;
  esac

  if [[ -n "$E2E_RESULTS_JSONL" ]] && have_tool python3; then
    mkdir -p "$(dirname "$E2E_RESULTS_JSONL")"
    python3 - "$E2E_RESULTS_JSONL" "$id" "$tier" "$status" "$summary" "$detail" <<'PY'
import json, sys
path, cid, tier, status, summary, detail = sys.argv[1:7]
entry = {
    "id": cid,
    "tier": tier,
    "status": status,
    "summary": summary,
    "detail": detail,
}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry) + "\n")
PY
  fi
}

# Execution-verified tool probe: rejects inactive mise shims (e.g. terraform, aws)
# that exist on PATH via command -v but fail when invoked.
have_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || return 1
  case "$tool" in
    bash)       bash --version >/dev/null 2>&1 ;;
    shellcheck) shellcheck --version >/dev/null 2>&1 ;;
    helm)       helm version --short >/dev/null 2>&1 ;;
    kustomize)  kustomize version >/dev/null 2>&1 ;;
    kubectl)    kubectl version --client >/dev/null 2>&1 ;;
    promtool)   promtool --version >/dev/null 2>&1 ;;
    terraform)  terraform version >/dev/null 2>&1 ;;
    python3)    python3 --version >/dev/null 2>&1 ;;
    git)        git --version >/dev/null 2>&1 ;;
    go)         go version >/dev/null 2>&1 ;;
    yamllint)   yamllint --version >/dev/null 2>&1 ;;
    jq)         jq --version >/dev/null 2>&1 ;;
    yq)         yq --version >/dev/null 2>&1 ;;
    trivy)      trivy --version >/dev/null 2>&1 ;;
    cosign)     cosign version >/dev/null 2>&1 ;;
    argocd)     argocd version --client >/dev/null 2>&1 ;;
    aws)        aws --version >/dev/null 2>&1 ;;
    kind)       kind version >/dev/null 2>&1 ;;
    docker)     docker --version >/dev/null 2>&1 ;;
    k6)         k6 version >/dev/null 2>&1 ;;
    curl)       curl --version >/dev/null 2>&1 ;;
    velero)     velero version --client-only >/dev/null 2>&1 ;;
    kyverno)    kyverno version >/dev/null 2>&1 ;;
    openssl)    openssl version >/dev/null 2>&1 ;;
    *)          "$tool" --version >/dev/null 2>&1 || "$tool" version >/dev/null 2>&1 ;;
  esac
}

have_docker_daemon() {
  have_tool docker && docker info >/dev/null 2>&1
}

have_pyyaml() {
  have_tool python3 && python3 -c "import yaml" >/dev/null 2>&1
}

require_tool() {
  local tool="$1"
  if ! have_tool "$tool"; then
    printf 'ERROR: Required tool not available or inactive shim: %s\n' "$tool" >&2
    return 1
  fi
}

# Default target context never falls back to ambient kubectl current-context.
resolve_apollo_context() {
  printf '%s' "${KUBE_CONTEXT:-kind-apollo11}"
}

# Strict allowlist: only kind-apollo11 or kind-apollo11-dev are permitted.
validate_apollo_context() {
  local ctx="$1"
  if [[ "$ctx" != kind-apollo11* ]]; then
    printf 'ERROR: Refusing context %q — must start with kind-apollo11.\n' "$ctx" >&2
    return 1
  fi
  case "$ctx" in
    kind-apollo11|kind-apollo11-dev)
      return 0
      ;;
    *)
      printf 'ERROR: Refusing context %q — stage scripts only permit kind-apollo11 or kind-apollo11-dev.\n' "$ctx" >&2
      return 1
      ;;
  esac
}

capture_orig_kube_context() {
  kubectl config current-context 2>/dev/null || true
}

print_e2e_summary() {
  local total=$((E2E_PASSED + E2E_FAILED + E2E_SKIPPED))
  printf '\n=== E2E Summary ===\n'
  printf 'Total: %d | Passed: %d | Failed: %d | Skipped: %d | Warnings: %d\n' \
    "$total" "$E2E_PASSED" "$E2E_FAILED" "$E2E_SKIPPED" "$E2E_WARNED"
}
