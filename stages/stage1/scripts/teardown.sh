#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s [--context kind-apollo11|kind-apollo11-dev] [kind-apollo11|kind-apollo11-dev]\n' "$0"
  printf '  --context CTX  Kubernetes context (or set KUBE_CONTEXT)\n'
}

CONTEXT="${KUBE_CONTEXT:-}"
CONTEXT_SET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      [[ $# -ge 2 ]] || { printf 'Missing value for --context\n' >&2; usage >&2; exit 2; }
      CONTEXT="$2"
      CONTEXT_SET=true
      shift 2
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
      if [[ "${CONTEXT_SET}" == false ]]; then
        CONTEXT="$1"
        CONTEXT_SET=true
        shift
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ "${CONTEXT_SET}" == false && -z "${CONTEXT}" ]]; then
  CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 1 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

kubectl --context "${CONTEXT}" delete namespace apollo-airlines --ignore-not-found --wait=true

if kubectl --context "${CONTEXT}" get namespace apollo-airlines >/dev/null 2>&1; then
  printf 'Stage 1 teardown failed: namespace still exists.\n' >&2
  exit 1
fi

printf 'Stage 1 teardown complete; cluster %s was retained.\n' "${CONTEXT#kind-}"
