# Measure search before changing it

Run from the Apollo11 repository root after building and installing the updated
Stage 7 snapshot. Use the same kind cluster, seeded date, request rate, image,
and replica count for both runs. Record `git rev-parse HEAD`, `git diff --stat`,
node capacity, and `kubectl top pods` with each result. The cache switch below
requires the updated Search image; a stale `:latest` image is not a baseline.

The benchmark uses six seeded routes, warms those keys outside the measured
scenario, then sends 50 requests/second for two minutes. Checks require actual
flight results; a fast empty response or a dropped iteration fails the run.
Thresholds are lab acceptance criteria, not a production SLO. k6 thresholds
control the process exit status; see the [k6 threshold reference](https://grafana.com/docs/k6/latest/using-k6/thresholds/).

1. In a dedicated terminal, bypass the Gateway and forward the Search Service.
   Both runs use this same route. This measures the application, not edge TLS.

   ```bash
   kubectl --context kind-apollo11 -n apollo-airlines-apps port-forward service/search 18083:8083
   ```

2. Record and temporarily pause the HPA. Save the original replica count and
   cache setting so recovery restores your starting point, including on error.
   Run the following in one Bash terminal:

   ```bash
   set -euo pipefail
   export KUBE_CONTEXT=kind-apollo11
   kube() { kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps "$@"; }
   baseline_dir=$(mktemp -d)
   kube get hpa search-hpa -o json | python3 -c '
   import json,sys
   d=json.load(sys.stdin); d.pop("status", None)
   for k in ("resourceVersion", "uid", "creationTimestamp", "managedFields"):
       d["metadata"].pop(k, None)
   print(json.dumps(d))' > "$baseline_dir/hpa.json"
   original_replicas=$(kube get deployment search -o jsonpath='{.spec.replicas}')
   original_cache=$(kube get deployment search -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CACHE_ENABLED")].value}')
   restore_baseline() {
     result=$?
     set +e
     recovery_failed=false
     kube set env deployment/search CACHE_ENABLED="${original_cache:-true}" || recovery_failed=true
     kube scale deployment/search --replicas="$original_replicas" || recovery_failed=true
     kube rollout status deployment/search --timeout=120s || recovery_failed=true
     kube apply -f "$baseline_dir/hpa.json" || recovery_failed=true
     if [[ "$recovery_failed" == true ]]; then
       echo "Recovery failed; saved HPA remains at $baseline_dir/hpa.json" >&2
       exit 1
     fi
     rm -rf "$baseline_dir"
     exit "$result"
   }
   trap restore_baseline EXIT
   kube delete hpa search-hpa
   kube scale deployment/search --replicas=1
   export SEARCH_DATE=$(date -u +%F)
   ```

3. Disable caching explicitly and wait for replacement Pods. Run the benchmark
   with `EXPECT_CACHE=off`; it must observe only MISS responses.

   ```bash
   kube set env deployment/search CACHE_ENABLED=false
   kube rollout status deployment/search --timeout=120s
   BASE_URL=http://localhost:18083 EXPECT_CACHE=off \
     k6 run --summary-export baseline-summary.json stages/stage7/k6/search.js
   ```

4. Restart the port-forward if the rollout ended it. Enable caching, use the
   same date and request rate, and require a hit rate above 90%:

   ```bash
   kube set env deployment/search CACHE_ENABLED=true
   kube rollout status deployment/search --timeout=120s
   BASE_URL=http://localhost:18083 EXPECT_CACHE=on \
     k6 run --summary-export optimized-summary.json stages/stage7/k6/search.js
   jq '.metrics | {http_req_duration, http_req_failed, checks, cache_hit_rate, dropped_iterations}' \
     baseline-summary.json optimized-summary.json
   ```

5. Exit that Bash terminal to trigger recovery. Check that the HPA is back,
   replicas stabilize, and a real search still returns flights. Keep both
   summaries and the environment record. A higher hit rate does not guarantee
   lower latency on a small local dataset; report the measured outcome.

If setup reports no seeded flights, inspect seed Jobs and choose a date within
the current data range using `SEARCH_DATE`. Reseed an old persistent database
rather than weakening the response check. Read error bodies before interpreting
HTTP latency. Inspect CPU, request rate, and dropped iterations alongside p95.

Explain: which variable changed, which stayed fixed, why warming is separate
from measurement, and whether the data supports enabling the cache.
