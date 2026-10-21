# Performance, correctness, and normal-policy scaling

Run the [cache benchmark](k6/README.md) first. It isolates cache impact with
one replica. Then use this lab to measure the normal HPA policy. A cache hit
ratio is not a capacity result, and a fast stale response is not a reservation.

## Build and inspect

Install Stage 7 Helm/dev, run its verifier, and record the revision, dirty diff,
node capacity, cache setting, and HPA specification. Use a quiet host: the
existing six-core/16 GiB host has shown load-sensitive failures. Budget at least
4 GiB of additional free memory for the full lab; this is a planning estimate,
not a measured minimum. Avoid concurrent image builds during measurements.
During the 2026-10-22 validation, load average exceeded 30 on six cores and
Identity exceeded its 30-second startup window. A temporary 180-second window
allowed focused observability checks to finish; this is not a stock lifecycle pass.

```bash
export KUBE_CONTEXT=kind-apollo11
kube() { kubectl --context "$KUBE_CONTEXT" "$@"; }
kube -n apollo-airlines-apps get hpa search-hpa -o yaml > /tmp/capacity-hpa-before.yaml
kube top nodes
kube -n apollo-airlines-apps get hpa search-hpa -w
```

In another terminal run the load through the Gateway, with trusted local TLS
and name resolution configured as described in README.md. Do not port-forward
a single Pod for this exercise: that would bypass Service load balancing.

k6 must trust the lab's self-signed edge certificate, which your host does not
trust by default. Point it at a copy of the certificate for this run only:

```bash
kubectl -n apollo-airlines-apps get secret apollo-edge-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/apollo-edge.crt
SSL_CERT_FILE=/tmp/apollo-edge.crt BASE_URL=https://search.apollo.local \
  k6 run --summary-export capacity.json k6/capacity.js
```

The 14-minute profile ramps 10→50→100→200 requests/s and returns to 10.
Record Pod CPU, desired/current replicas, pending Pods, p95, failures and dropped
iterations. Retain `kubectl describe hpa search-hpa` alongside the summary.
Normal CPU target and stabilization remain unchanged. Cached Search may never
cross the CPU target: report that outcome rather than lowering the target.
A failed threshold identifies the tested capacity boundary, not a broken HPA.

## Break and recover the cache

Save Redis's original replica count and restore it even if the experiment fails:

```bash
original=$(kube -n apollo-airlines-apps get sts redis -o jsonpath='{.spec.replicas}')
trap 'kube -n apollo-airlines-apps scale sts/redis --replicas="$original"' EXIT
kube -n apollo-airlines-apps scale sts/redis --replicas=0
kube -n apollo-airlines-apps wait --for=delete pod/redis-0 --timeout=120s
curl --fail -D - "https://search.apollo.local/api/search?origin=BOM&destination=SIN&date=$(date -u +%F)"
# Require 200, real results, X-Cache: MISS. Record latency and Search logs.
kube -n apollo-airlines-apps scale sts/redis --replicas="$original"
kube -n apollo-airlines-apps rollout status sts/redis --timeout=180s
# Repeat the same request twice; require HIT after the cache repopulates.
trap - EXIT
```

Notification also uses Redis: inspect its readiness during this outage.

## Stale availability and concurrent misses

Search stores availability for 300 seconds. Warm a route, create a booking using
the frontend, and compare the cached Search result with Flight's live result.
Search may show the previous seat count. Cancel the booking and prove Flight's
seat count recovers. Wait for expiry and require a fresh MISS then HIT.
Booking must validate live availability; Search is never a seat reservation.

`go test -race ./...` in `code/search` exercises the actual HTTP handler against
a simulated Redis server and HTTP upstream: MISS/HIT, TTL expiry, stale values,
concurrent cold misses, upstream errors, Redis errors, and recovery. It does not
claim distributed singleflight: several simultaneous cold requests can reach
Flight. Compare upstream request counts during cold and warm load before
choosing whether request coalescing is warranted.

## Required VPA recommendation exercise

Dev deliberately skips VPA. Finish and tear down dev, then install staging:

```bash
bash scripts/teardown.sh --mode helm --env dev --purge
bash scripts/apply.sh --mode helm --env staging
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get vpa search-vpa -w
```

Run representative traffic and wait for a nonempty recommendation. Record lower,
target and upper bounds plus the current requests. Explain whether the sample
history is representative. VPA stays `Off`: no automatic resource mutations.
Save your values file before trying a recommendation through Helm, rerun the
same load, and restore those values to recover. Compare p95, CPU throttling and
HPA replicas. Changing CPU requests changes HPA utilization's denominator.

Finish with the stage teardown and residue checks. Explain why cache impact,
capacity, horizontal scaling and vertical recommendations require different
experiments, and why a short local test cannot establish production capacity.
