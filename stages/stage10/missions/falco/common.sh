#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISSION=apollo11-falco
# A private kubeconfig avoids changing the learner's active context.
export KUBECONFIG="$DIR/.kubeconfig"
kube() { kubectl --context "kind-$MISSION" "$@"; }
