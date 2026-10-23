#!/usr/bin/env bash
# Local equivalent of CI's validation job. Run from any working directory.
set -euo pipefail
cd "$(dirname "$0")/.."
# Record the toolchain so local and hosted results can be compared.
printf 'helm %s | %s | %s | shellcheck %s\n' "$(helm version --short)" \
  "$(kubectl version --client 2>/dev/null | head -1)" "$(go version)" \
  "$(shellcheck --version | sed -n 's/^version: //p')"
# generated.yaml files are byte-compared against Helm 4 output; Helm 3
# renders different whitespace and would report them as stale.
if [[ "$(helm version --template '{{.Version}}')" != v4.* ]]; then
  echo 'test/ci.sh needs Helm 4 (the committed generated.yaml files are Helm 4 renders).' >&2
  exit 1
fi
python3 test/generated.py --check
python3 -m unittest discover -s test/review -v
for stage in 5 6 7; do
  dir="stages/stage$stage"
  helm lint "$dir/helm/apollo11"
  for env in dev staging prod; do
    helm lint "$dir/helm/apollo11" -f "$dir/helm/apollo11/values-$env.yaml"
    helm template apollo11 "$dir/helm/apollo11" -f "$dir/helm/apollo11/values-$env.yaml" >/dev/null
    kubectl kustomize "$dir/overlays/$env" >/dev/null
  done
  bash "$dir/argocd/scripts/validate.sh"
  for service in flight booking search notification; do
    (cd "$dir/code/$service" && go test -race ./...)
  done
done
# Every stage script is checked, including optional missions and legacy trees.
find stages -type f -name '*.sh' -print0 | xargs -0 shellcheck -S warning
