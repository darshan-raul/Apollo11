# Gap-closure regression checks

Run from the Apollo11 root with Python 3, PyYAML, Helm, and kubectl available:

```bash
python3 -m unittest discover -s test/review -v
(cd stages/stage7/code/search && go test ./...)
```

The CLI fakes isolate EBS deletion, context selection, certificate preservation,
shared-platform purge rejection, and the HTTPS workflow from real services.
Render tests use actual Helm/Kustomize and inspect all 18 environment/mode
combinations. They also check TLS disabling, deterministic renders, the cache
switch, and cumulative signal selection.

These are regression checks for destructive boundaries and cross-tool contracts.
They do not replace real TLS, AWS, browser, SLO, k6, Argo, or stage lifecycles.
Run the Prometheus fixture separately with promtool after extracting the chart's
PrometheusRule `spec` to `rules.yaml` beside `test/stage6_slo_rules_test.yaml`.
