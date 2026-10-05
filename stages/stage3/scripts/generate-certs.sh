#!/usr/bin/env bash
set -euo pipefail
CONTEXT="${KUBE_CONTEXT:-}"
APPS_NAMESPACE=apollo-airlines-apps
UI_NAMESPACE=apollo-airlines-ui
ROTATE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="$2"; shift 2 ;;
    --apps-namespace) APPS_NAMESPACE="$2"; shift 2 ;;
    --ui-namespace) UI_NAMESPACE="$2"; shift 2 ;;
    --rotate) ROTATE=true; shift ;;
    *) echo "Usage: $0 [--context kind-apollo11|kind-apollo11-dev] [--rotate]" >&2; exit 2 ;;
  esac
done
CONTEXT="${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}"
case "$CONTEXT" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) echo "Refusing certificate changes in context '${CONTEXT:-<none>}'" >&2; exit 2 ;;
esac
kube() { kubectl --context "$CONTEXT" "$@"; }
CERT_DIR="$(mktemp -d)"
trap 'rm -rf "$CERT_DIR"' EXIT
umask 077
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" \
  -subj '/CN=*.apollo.local' \
  -addext 'subjectAltName=DNS:*.apollo.local,DNS:apollo.local' >/dev/null 2>&1
for ns in "$APPS_NAMESPACE" "$UI_NAMESPACE"; do
  kube get namespace "$ns" >/dev/null
  # --ignore-not-found distinguishes absence from authorization/connectivity errors.
  existing=$(kube get secret apollo-tls-secret -n "$ns" -o name --ignore-not-found)
  if [[ "$ROTATE" == false && -n "$existing" ]]; then
    echo "Preserving apollo-tls-secret in $ns (use --rotate to renew)."
    continue
  fi
  kube create secret tls apollo-tls-secret --cert="$CERT_DIR/tls.crt" \
    --key="$CERT_DIR/tls.key" -n "$ns" --dry-run=client -o yaml | kube apply -f -
done
