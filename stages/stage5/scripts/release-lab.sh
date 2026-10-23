#!/usr/bin/env bash
# Stage 5 Helm release lab: break a release with a bad upgrade, diagnose it,
# roll back, and prove recovery with behavior and `helm test`.
#
# Usage: bash scripts/release-lab.sh [--release NAME]
# Needs a Helm install from `scripts/apply.sh --mode helm` (any env).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$STAGE_DIR/helm/apollo11"
RELEASE=apollo11
NS=apollo-airlines-apps
BAD_TAG=missing-release-lab

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE="$2"; shift 2 ;;
    --help) sed -n 2,6p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# shellcheck source=context.sh
source "$SCRIPT_DIR/context.sh"
apollo_context_guard

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
step() { printf '\n== %s\n' "$1"; }
search_ready() {  # call search from inside the cluster, as booking would
  kubectl -n "$NS" exec deploy/booking -- wget -qO- -T 5 http://search:8083/healthz/ready >/dev/null 2>&1
}

step "Inspect: the release and its history"
helm status "$RELEASE" -n "$NS" >/dev/null || { echo "No Helm release '$RELEASE' in $NS; run scripts/apply.sh --mode helm first." >&2; exit 2; }
helm history "$RELEASE" -n "$NS" --max 5
GOOD_REV=$(helm history "$RELEASE" -n "$NS" -o json | python3 -c 'import json,sys; print([r for r in json.load(sys.stdin) if r["status"]=="deployed"][-1]["revision"])')
GOOD_TAG=$(kubectl -n "$NS" get deploy search -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Deployed revision: $GOOD_REV (search image $GOOD_TAG)"

step "Break: upgrade with an image tag that does not exist"
if helm upgrade "$RELEASE" "$CHART_DIR" -n "$NS" --reuse-values \
     --set image.tag="$BAD_TAG" --wait --timeout 90s; then
  fail "upgrade with tag $BAD_TAG should not have succeeded"
else
  pass "helm upgrade --wait failed instead of reporting success"
fi
status=$(helm status "$RELEASE" -n "$NS" -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["status"])')
[[ "$status" == failed ]] && pass "release status is 'failed'" || fail "release status is '$status', expected 'failed'"
reason=$(kubectl -n "$NS" get pods -l app=search -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{" "}{end}')
echo "search Pod waiting reasons: ${reason:-<none>}"
[[ "$reason" == *ImagePull* || "$reason" == *ErrImage* ]] && pass "new search Pod shows an image pull error" || fail "no image pull error on search Pods"
search_ready && pass "old search Pod still serves during the failed release" || fail "search stopped serving during the failed release"

step "Recover: roll back to revision $GOOD_REV"
helm rollback "$RELEASE" "$GOOD_REV" -n "$NS" --wait --timeout 5m
helm history "$RELEASE" -n "$NS" --max 4
latest=$(helm history "$RELEASE" -n "$NS" -o json | python3 -c 'import json,sys; r=json.load(sys.stdin)[-1]; print(r["status"], r["description"])')
[[ "$latest" == "deployed Rollback to $GOOD_REV" ]] && pass "latest revision is 'Rollback to $GOOD_REV' and deployed" || fail "latest revision is '$latest'"
now_tag=$(kubectl -n "$NS" get deploy search -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "$now_tag" == "$GOOD_TAG" ]] && pass "search image restored to $GOOD_TAG" || fail "search image is $now_tag"
search_ready && pass "search serves after rollback" || fail "search does not serve after rollback"

step "Prove: helm test"
if helm test "$RELEASE" -n "$NS" --logs --timeout 3m; then
  pass "helm test passed after rollback"
else
  fail "helm test failed after rollback"
fi

printf '\nRelease lab: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
