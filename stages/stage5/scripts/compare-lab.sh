#!/usr/bin/env bash
# Stage 5 Helm vs Kustomize comparison lab (render only, no cluster needed).
#
# 1. Render dev and prod with both tools and compare what each environment
#    changes.
# 2. Make the same change in both tools (search: 3 replicas in dev) and prove
#    the two renders agree on it.
#
# Usage: bash scripts/compare-lab.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART="$STAGE_DIR/helm/apollo11"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

helm_render() { helm template apollo11 "$CHART" -f "$CHART/values-$1.yaml" "${@:2}"; }
summary() {  # replicas, search image and PDB count from a rendered stream
  python3 -c '
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
deps = {d["metadata"]["name"]: d for d in docs if d["kind"] == "Deployment"}
s = deps["search"]
print("search replicas=%s image=%s pdbs=%d" % (s["spec"]["replicas"],
      s["spec"]["template"]["spec"]["containers"][0]["image"],
      sum(1 for d in docs if d["kind"] == "PodDisruptionBudget")))'
}

echo "== 1. What each environment changes"
for env in dev prod; do
  echo "helm      $env: $(helm_render "$env" | summary)"
  echo "kustomize $env: $(kubectl kustomize "$STAGE_DIR/overlays/$env" | summary)"
done
echo "Helm expresses environments as values files; Kustomize as overlays that patch a base."

echo
echo "== 2. The same change in both tools: search replicas 3 in dev"
helm_out=$(helm_render dev --set apps.search.replicas=3 | summary)
mkdir -p "$WORK/search-x3"
cat >"$WORK/search-x3/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - $(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$STAGE_DIR/overlays/dev" "$WORK/search-x3")
replicas:
  - name: search
    count: 3
EOF
# The temporary overlay lives outside the repo, so allow it to load the dev
# overlay by relative path.
kust_out=$(kubectl kustomize --load-restrictor LoadRestrictionsNone "$WORK/search-x3" | summary)
echo "helm --set apps.search.replicas=3 -> $helm_out"
echo "kustomize replicas patch          -> $kust_out"
[[ "$helm_out" == *"replicas=3"* ]] && pass "Helm render has 3 search replicas" || fail "Helm render: $helm_out"
[[ "$kust_out" == *"replicas=3"* ]] && pass "Kustomize render has 3 search replicas" || fail "Kustomize render: $kust_out"

printf '\nCompare lab: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
