#!/usr/bin/env bash
# Bind every Kubernetes/Helm operation to the checked local context.
apollo_context_guard() {
    APOLLO_CONTEXT="${KUBE_CONTEXT:-$(command kubectl config current-context 2>/dev/null || true)}"
    case "$APOLLO_CONTEXT" in
        kind-apollo11|kind-apollo11-dev) ;;
        *) echo "Refusing context '${APOLLO_CONTEXT:-<none>}'; expected kind-apollo11 or kind-apollo11-dev." >&2; return 2 ;;
    esac
    export KUBE_CONTEXT="$APOLLO_CONTEXT"
}
kubectl() { command kubectl --context "$APOLLO_CONTEXT" "$@"; }
helm() { command helm --kube-context "$APOLLO_CONTEXT" "$@"; }

# CRD deletion also removes every instance. Refuse a purge of a shared platform.
apollo_assert_exclusive_platform() {
    local crds resource payload
    crds=$(kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}') || return 1
    while IFS= read -r resource; do
        [[ "$resource" =~ (gateway\.networking\.k8s\.io|gateway\.envoyproxy\.io|metallb\.io)$ ]] || continue
        payload=$(kubectl get "$resource" --all-namespaces -o json) || return 1
        if ! python3 -c '
import json,sys
for item in json.load(sys.stdin)["items"]:
    m=item["metadata"]; ns=m.get("namespace", ""); name=m["name"]
    owned = ns in ("apollo-airlines-apps", "apollo-airlines-ui")
    owned |= ns == "metallb-system" and name in ("apollo-pool", "apollo-l2")
    owned |= not ns and item["kind"] == "GatewayClass" and name == "eg"
    if not owned:
        print("Refusing platform purge: resource outside this snapshot: " + item["kind"] + "/" + name + " in " + (ns or "<cluster>"), file=sys.stderr)
        sys.exit(1)
' <<< "$payload"; then return 1; fi
    done <<< "$crds"
}
