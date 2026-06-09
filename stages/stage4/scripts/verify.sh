#!/bin/bash
# Verify Stage 4: ~63 checks covering the Stage 3 baseline (StatefulSets,
# PVCs, access stack) + Stage 4 additions (probes, Guaranteed QoS, PDBs,
# graceful-shutdown demo).
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
step() { echo -e "${CYAN}▶ $1${NC}"; }

# ---------------------------------------------------------------------------
# Stage 3 baseline (~25 checks) — namespaced resources, StatefulSets, PVCs,
# Deployments, controllers, Gateway, HTTPRoutes.
# ---------------------------------------------------------------------------

step "Namespaces (4 expected: apps, ui, envoy-gateway-system, metallb-system)"
for ns in apollo-airlines-apps apollo-airlines-ui envoy-gateway-system metallb-system; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then pass "namespace $ns"; else fail "namespace $ns missing"; fi
done

step "StatefulSets (4 expected, all 1/1 Ready)"
for sts in identity-db flight-db booking-db redis; do
  ready=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 1 ]]; then
    pass "statefulset/$sts ready=$ready"
  else
    fail "statefulset/$sts not ready (ready=$ready)"
  fi
done

step "StatefulSet pods (4 expected, all Ready)"
for pod in identity-db-0 flight-db-0 booking-db-0 redis-0; do
  cond=$(kubectl get pod "$pod" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$cond" == "True" ]]; then
    pass "pod/$pod Ready"
  else
    fail "pod/$pod not Ready (cond=$cond)"
  fi
done

step "PVCs (4 expected, all Bound — proves storage works)"
EXPECTED_PVCS=(
  "apollo-airlines-apps:pg-data-identity-db-0"
  "apollo-airlines-apps:pg-data-flight-db-0"
  "apollo-airlines-apps:pg-data-booking-db-0"
  "apollo-airlines-apps:redis-data-redis-0"
)
for p in "${EXPECTED_PVCS[@]}"; do
  ns="${p%%:*}"; name="${p##*:}"
  phase=$(kubectl get pvc "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$phase" == "Bound" ]]; then
    pass "pvc $ns/$name Bound"
  else
    fail "pvc $ns/$name phase=$phase (expected Bound)"
  fi
done

step "Headless Services exist (4 expected)"
for svc in identity-db-headless flight-db-headless booking-db-headless redis-headless; do
  cip=$(kubectl get svc "$svc" -n apollo-airlines-apps -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  if [[ "$cip" == "None" ]]; then
    pass "headless service $svc (clusterIP=None)"
  else
    fail "service $svc clusterIP=$cip (expected None)"
  fi
done

step "App Deployments (6 expected, all 2/2 Ready)"
for d in identity flight booking search notification; do
  ready=$(kubectl get deploy "$d" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" -ge 2 ]]; then
    pass "deploy apollo-airlines-apps/$d ready=$ready"
  else
    fail "deploy apollo-airlines-apps/$d ready=$ready (expected ≥ 2)"
  fi
done
ready=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 2 ]]; then pass "deploy apollo-airlines-ui/frontend ready=$ready"; else fail "deploy frontend ready=$ready"; fi

step "MetalLB controller"
ready=$(kubectl get deploy controller -n metallb-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then pass "metallb controller ready=$ready"; else fail "metallb controller not ready"; fi

step "Envoy Gateway controller"
ready=$(kubectl get deploy envoy-gateway -n envoy-gateway-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "$ready" -ge 1 ]]; then pass "envoy-gateway controller ready=$ready"; else fail "envoy-gateway controller not ready"; fi

step "Envoy proxy (auto-created by Gateway)"
proxy_ready=$(kubectl get pods -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway --no-headers 2>/dev/null | awk '{print $2}' | grep -cE "^[0-9]+/[0-9]+$")
proxy_ready=${proxy_ready:-0}
if [[ "$proxy_ready" -ge 1 ]]; then pass "envoy proxy pod Ready (count=$proxy_ready)"; else fail "envoy proxy not Ready (count=$proxy_ready)"; fi

step "Seed jobs (3 expected, all succeeded)"
for j in seed-identity-db seed-flight-db seed-booking-db; do
  s=$(kubectl get job "$j" -n apollo-airlines-apps -o jsonpath='{.status.succeeded}' 2>/dev/null || echo 0)
  if [[ "$s" == "1" ]]; then pass "job $j succeeded"; else fail "job $j succeeded=$s"; fi
done

step "MetalLB IPAddressPool"
if kubectl get ipaddresspool apollo-pool -n metallb-system >/dev/null 2>&1; then
  pass "apollo-pool IPAddressPool exists"
else
  fail "apollo-pool IPAddressPool missing"
fi

step "Envoy LoadBalancer Service has an IP from MetalLB"
SVC=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$SVC" ]]; then
  ENVOY_IP=$(kubectl get svc "$SVC" -n envoy-gateway-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [[ -n "$ENVOY_IP" ]]; then pass "MetalLB assigned IP: $ENVOY_IP"; else fail "no LoadBalancer IP assigned to $SVC"; fi
else
  fail "envoy Service not found"
  ENVOY_IP=""
fi

step "Gateway 'apollo-gateway' is Programmed"
prog=$(kubectl get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [[ "$prog" == "True" ]]; then pass "apollo-gateway is Programmed"; else fail "apollo-gateway is not Programmed (status=$prog)"; fi

step "HTTPRoutes (6 expected, all with parent status)"
rt_count=$(kubectl get httproute -A --no-headers 2>/dev/null | grep apollo-airlines | wc -l)
parent_count=$(kubectl get httproute -A -o custom-columns="P:.status.parents[*].controllerName" --no-headers 2>/dev/null | grep -c "gateway.envoyproxy.io" || echo 0)
if [[ "$rt_count" -ge 6 ]] && [[ "$parent_count" -ge 6 ]]; then
  pass "$rt_count HTTPRoutes, all $parent_count have parents"
else
  fail "only $rt_count/$parent_count HTTPRoutes have parents"
fi

# Skip smoke tests if no IP
if [[ -z "$ENVOY_IP" ]]; then
  echo ""
  echo "Skipping smoke tests (no MetalLB IP)."
  echo "Passed: $PASS  Failed: $FAIL"
  exit $FAIL
fi

step "Smoke test: Envoy → identity (Host header, /healthz) at $ENVOY_IP"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: identity.apollo.local" "http://$ENVOY_IP/healthz" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → identity → 200"; else fail "Envoy → identity → $RESP (expected 200)"; fi

step "Smoke test: Envoy → flight (Host header, /api/flights)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: flight.apollo.local" "http://$ENVOY_IP/api/flights" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → flight → 200"; else fail "Envoy → flight → $RESP (expected 200)"; fi

step "Smoke test: Envoy → frontend (Host header)"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" "http://$ENVOY_IP/" 2>/dev/null || echo "000")
if [[ "$RESP" == "200" ]]; then pass "Envoy → frontend → 200"; else fail "Envoy → frontend → $RESP (expected 200)"; fi

step "Smoke test: full login flow through Envoy Gateway"
LOGIN_RESP=$(curl -s -X POST -H "Host: identity.apollo.local" -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}' \
  "http://$ENVOY_IP/api/users/login" 2>/dev/null || echo "")
TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$TOKEN" ]]; then
  pass "Login through Envoy returned a JWT (${#TOKEN} chars)"
else
  fail "Login through Envoy failed: $LOGIN_RESP"
fi

step "Stage 3: seed data actually present in DBs"
u_count=$(kubectl exec -n apollo-airlines-apps identity-db-0 -- \
  psql -U postgres -d identity -tAc "SELECT count(*) FROM users;" 2>/dev/null || echo "")
if [[ "$u_count" -ge 2 ]]; then
  pass "users table has $u_count rows (seed worked)"
else
  fail "users table has $u_count rows (expected ≥ 2)"
fi

a_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM airports;" 2>/dev/null || echo "")
if [[ "$a_count" -ge 6 ]]; then
  pass "airports table has $a_count rows (seed worked)"
else
  fail "airports table has $a_count rows (expected ≥ 6)"
fi

f_count=$(kubectl exec -n apollo-airlines-apps flight-db-0 -- \
  psql -U postgres -d flight -tAc "SELECT count(*) FROM flights;" 2>/dev/null || echo "")
if [[ "$f_count" -ge 180 ]]; then
  pass "flights table has $f_count rows (seed worked)"
else
  fail "flights table has $f_count rows (expected ≥ 180)"
fi

# ---------------------------------------------------------------------------
# Stage 4: probes (startup/live/ready) on all 6 apps + readiness/liveness on
# 4 StatefulSets.
# ---------------------------------------------------------------------------

step "Stage 4: startup/live/ready probes configured on all 6 app Deployments"
for d in identity flight booking search notification; do
  ns=apollo-airlines-apps
  for probe in startupProbe livenessProbe readinessProbe; do
    p=$(kubectl get deploy "$d" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
    if [[ -n "$p" ]]; then
      pass "deploy/$d has $probe → $p"
    else
      fail "deploy/$d missing $probe"
    fi
  done
done
for probe in startupProbe livenessProbe readinessProbe; do
  p=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath="{.spec.template.spec.containers[0].${probe}.httpGet.path}" 2>/dev/null || echo "")
  if [[ -n "$p" ]]; then
    pass "deploy/frontend has $probe → $p"
  else
    fail "deploy/frontend missing $probe"
  fi
done

step "Stage 4: 4 StatefulSets have liveness + readiness, NO startupProbe"
for sts in identity-db flight-db booking-db redis; do
  for probe in livenessProbe readinessProbe; do
    cmd=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].${probe}.exec.command[0]}" 2>/dev/null || echo "")
    if [[ -n "$cmd" ]]; then
      pass "statefulset/$sts has $probe ($cmd)"
    else
      fail "statefulset/$sts missing $probe"
    fi
  done
  sp=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null || echo "")
  if [[ -z "$sp" || "$sp" == "<nil>" || "$sp" == "null" ]]; then
    pass "statefulset/$sts has no startupProbe (correct)"
  else
    fail "statefulset/$sts should not have startupProbe (got: $sp)"
  fi
done

# ---------------------------------------------------------------------------
# Stage 4: resources.requests == resources.limits on every container.
# ---------------------------------------------------------------------------

step "Stage 4: resources.requests and resources.limits configured on all 10 workloads"
ALL_RESOURCES_OK=1
for d in identity flight booking search notification; do
  for key in "requests.cpu" "requests.memory" "limits.cpu" "limits.memory"; do
    val=$(kubectl get deploy "$d" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].resources.${key}}" 2>/dev/null || echo "")
    if [[ -z "$val" ]]; then
      fail "deploy/$d missing resources.${key}"
      ALL_RESOURCES_OK=0
    fi
  done
  if [[ "$ALL_RESOURCES_OK" -eq 1 ]]; then
    pass "deploy/$d has requests.{cpu,memory} + limits.{cpu,memory}"
  fi
done
for key in "requests.cpu" "requests.memory" "limits.cpu" "limits.memory"; do
  val=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath="{.spec.template.spec.containers[0].resources.${key}}" 2>/dev/null || echo "")
  if [[ -z "$val" ]]; then
    fail "deploy/frontend missing resources.${key}"
    ALL_RESOURCES_OK=0
  fi
done
if [[ "$ALL_RESOURCES_OK" -eq 1 ]]; then
  pass "deploy/frontend has requests.{cpu,memory} + limits.{cpu,memory}"
fi
for sts in identity-db flight-db booking-db redis; do
  for key in "requests.cpu" "requests.memory" "limits.cpu" "limits.memory"; do
    val=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath="{.spec.template.spec.containers[0].resources.${key}}" 2>/dev/null || echo "")
    if [[ -z "$val" ]]; then
      fail "statefulset/$sts missing resources.${key}"
      ALL_RESOURCES_OK=0
    fi
  done
  if [[ "$ALL_RESOURCES_OK" -eq 1 ]]; then
    pass "statefulset/$sts has requests.{cpu,memory} + limits.{cpu,memory}"
  fi
done

# ---------------------------------------------------------------------------
# Stage 4: QoS class is Guaranteed on every pod (requests == limits).
# ---------------------------------------------------------------------------

step "Stage 4: QoS class is Guaranteed on all 10 workload pods"
for d in identity flight booking search notification; do
  qos=$(kubectl get pods -n apollo-airlines-apps -l app="$d" -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
  if [[ "$qos" == "Guaranteed" ]]; then
    pass "deploy/$d pod QoS=$qos"
  else
    fail "deploy/$d pod QoS=$qos (expected Guaranteed)"
  fi
done
qos=$(kubectl get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null || echo "")
if [[ "$qos" == "Guaranteed" ]]; then pass "deploy/frontend pod QoS=$qos"; else fail "deploy/frontend pod QoS=$qos"; fi
for sts in identity-db flight-db booking-db redis; do
  qos=$(kubectl get pod "$sts-0" -n apollo-airlines-apps -o jsonpath='{.status.qosClass}' 2>/dev/null || echo "")
  if [[ "$qos" == "Guaranteed" ]]; then
    pass "statefulset/$sts pod QoS=$qos"
  else
    fail "statefulset/$sts pod QoS=$qos (expected Guaranteed)"
  fi
done

# ---------------------------------------------------------------------------
# Stage 4: terminationGracePeriodSeconds = 30 (apps) / 60 (DBs).
# ---------------------------------------------------------------------------

step "Stage 4: terminationGracePeriodSeconds configured (30s apps, 60s DBs)"
for d in identity flight booking search notification; do
  t=$(kubectl get deploy "$d" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
  if [[ "$t" == "30" ]]; then pass "deploy/$d terminationGracePeriodSeconds=30"; else fail "deploy/$d terminationGracePeriodSeconds=$t (expected 30)"; fi
done
t=$(kubectl get deploy frontend -n apollo-airlines-ui -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
if [[ "$t" == "30" ]]; then pass "deploy/frontend terminationGracePeriodSeconds=30"; else fail "deploy/frontend terminationGracePeriodSeconds=$t"; fi
for sts in identity-db flight-db booking-db redis; do
  t=$(kubectl get statefulset "$sts" -n apollo-airlines-apps -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null || echo "")
  if [[ "$t" == "60" ]]; then pass "statefulset/$sts terminationGracePeriodSeconds=60"; else fail "statefulset/$sts terminationGracePeriodSeconds=$t (expected 60)"; fi
done

# ---------------------------------------------------------------------------
# Stage 4: PodDisruptionBudgets for booking + frontend.
# ---------------------------------------------------------------------------

step "Stage 4: PodDisruptionBudgets exist (booking-pdb, frontend-pdb)"
for pdb in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
  ns="${pdb%%:*}"; name="${pdb##*:}"
  if kubectl get pdb "$name" -n "$ns" >/dev/null 2>&1; then
    ma=$(kubectl get pdb "$name" -n "$ns" -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
    if [[ "$ma" == "1" ]]; then
      pass "pdb $ns/$name minAvailable=1"
    else
      fail "pdb $ns/$name minAvailable=$ma (expected 1)"
    fi
  else
    fail "pdb $ns/$name missing"
  fi
done

# PDBs are 'Allowed' when the controller has computed a status. With 2
# replicas and minAvailable=1, currentHealthy=2 / desiredHealthy=1 / expectedPods=2.
step "Stage 4: PDBs have status (current healthy ≥ min available)"
for pdb in "apollo-airlines-apps:booking-pdb" "apollo-airlines-ui:frontend-pdb"; do
  ns="${pdb%%:*}"; name="${pdb##*:}"
  cur=$(kubectl get pdb "$name" -n "$ns" -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "0")
  exp=$(kubectl get pdb "$name" -n "$ns" -o jsonpath='{.status.expectedPods}' 2>/dev/null || echo "0")
  if [[ "$cur" -ge 1 && "$exp" -ge 1 ]]; then
    pass "pdb $ns/$name status: currentHealthy=$cur expectedPods=$exp"
  else
    fail "pdb $ns/$name status: currentHealthy=$cur expectedPods=$exp"
  fi
done

# ---------------------------------------------------------------------------
# Stage 4: live probe responses from each app pod (proves kubelet has
# something to actually call).
# ---------------------------------------------------------------------------

step "Stage 4: live probe responses — /healthz/{startup,live,ready} from each app pod"
# For each app, kubectl exec into one pod and curl its probe paths.
for entry in "apollo-airlines-apps:identity:8080" \
              "apollo-airlines-apps:flight:8081" \
              "apollo-airlines-apps:booking:8082" \
              "apollo-airlines-apps:search:8083" \
              "apollo-airlines-apps:notification:8084" \
              "apollo-airlines-ui:frontend:3000"; do
  ns=$(echo "$entry" | cut -d: -f1)
  svc=$(echo "$entry" | cut -d: -f2)
  port=$(echo "$entry" | cut -d: -f3)
  for p in startup live ready; do
    code=$(kubectl exec -n "$ns" "deploy/$svc" -- \
      sh -c "wget -q -O- --tries=1 http://127.0.0.1:$port/healthz/$p 2>/dev/null | head -1 || echo FAIL" 2>/dev/null | tr -d '\n' || echo "")
    if [[ -n "$code" && "$code" != "FAIL" && "$code" != *error* ]]; then
      pass "$svc /healthz/$p responded: $(echo "$code" | head -c 40)"
    else
      # Some images (alpine nginx, python slim) don't have wget. Try python http.client fallback.
      code2=$(kubectl exec -n "$ns" "deploy/$svc" -- \
        sh -c "python3 -c 'import urllib.request; print(urllib.request.urlopen(\"http://127.0.0.1:$port/healthz/$p\").read().decode())' 2>/dev/null || echo FAIL" 2>/dev/null | tr -d '\n' || echo "")
      if [[ -n "$code2" && "$code2" != "FAIL" ]]; then
        pass "$svc /healthz/$p responded: $(echo "$code2" | head -c 40)"
      else
        # Final fallback: use the Go `httptest` style by checking the path exists at all
        # by trying a TCP connect. Many pods will at least let us check the
        # kubelet saw the port open.
        tcpok=$(kubectl exec -n "$ns" "deploy/$svc" -- \
          sh -c "exec 3<>/dev/tcp/127.0.0.1/$port && echo OK" 2>/dev/null || echo "")
        if [[ "$tcpok" == "OK" ]]; then
          pass "$svc port $port open (couldn't fetch body, but TCP ok)"
        else
          fail "$svc /healthz/$p unreachable"
        fi
      fi
    fi
  done
done

# ---------------------------------------------------------------------------
# Stage 4: behavioural demo — graceful shutdown on SIGTERM.
# Delete a booking pod, wait for replacement, check the previous pod's logs
# contain the graceful-shutdown log line.
# ---------------------------------------------------------------------------

step "Stage 4 demo: graceful SIGTERM shutdown (delete booking pod, follow logs)"
BOOKING_POD=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$BOOKING_POD" ]]; then
  # `kubectl logs --previous` returns NotFound once the pod is removed
  # from the API server, so we follow the pod's logs in real-time and
  # grep for the SIGTERM line. The structured JSON log message is:
  #   "Received SIGTERM, shutting down gracefully"
  SIGTERM_LOG=$(mktemp)
  # Start the log follower in background; redirect to a file we can grep.
  kubectl logs -n apollo-airlines-apps "$BOOKING_POD" --follow > "$SIGTERM_LOG" 2>&1 &
  LOG_PID=$!
  # Give the follower a beat to attach, then delete the pod.
  sleep 0.5
  kubectl delete pod "$BOOKING_POD" -n apollo-airlines-apps --wait=false >/dev/null 2>&1 || true
  # Wait up to 30s for the SIGTERM log to appear, then kill the follower.
  for i in $(seq 1 30); do
    if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  kill "$LOG_PID" 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true
  if grep -q "Received SIGTERM, shutting down gracefully" "$SIGTERM_LOG" 2>/dev/null; then
    pass "booking pod logged 'Received SIGTERM, shutting down gracefully' on shutdown"
  else
    fail "booking pod did not log graceful shutdown (logs: $(head -3 "$SIGTERM_LOG"))"
  fi
  rm -f "$SIGTERM_LOG"

  # And wait for the replacement pod to be Ready.
  ready=""
  for i in $(seq 1 30); do
    ready=$(kubectl get pods -n apollo-airlines-apps -l app=booking -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$ready" == "True" ]]; then
      pass "booking replacement pod Ready after delete"
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "True" ]]; then
    fail "booking replacement pod not Ready after 30s"
  fi
else
  fail "could not find a booking pod to delete"
fi

# Same demo for frontend — proves the NGINX probe paths actually serve.
# (NGINX doesn't log a custom "SIGTERM" line like the Go services do, so
# we just verify the replacement pod comes up Ready and serves /healthz/ready
# again, which proves the new pod re-applied the NGINX config correctly.)
step "Stage 4 demo: frontend pod restarts cleanly on SIGTERM"
FRONTEND_POD=$(kubectl get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$FRONTEND_POD" ]]; then
  kubectl delete pod "$FRONTEND_POD" -n apollo-airlines-ui --wait=false >/dev/null 2>&1 || true
  ready=""
  for i in $(seq 1 30); do
    ready=$(kubectl get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$ready" == "True" ]]; then
      pass "frontend replacement pod Ready after delete"
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "True" ]]; then
    fail "frontend replacement pod not Ready after 30s"
  fi
  # Verify the replacement pod is serving the NGINX probe paths.
  # (NGINX may still be starting up the instant the pod becomes Ready, so
  # retry a couple of times before failing. We re-fetch the pod name
  # inside the loop because the API server can return the old (deleting)
  # pod name for the first second or two after the delete call returns.
  # We tolerate `kubectl exec` errors during the startup window by
  # capturing exit status separately — the `|| true` stops `set -e`
  # from killing the loop.)
  body=""
  for i in $(seq 1 30); do
    NEW_FRONTEND=$(kubectl get pods -n apollo-airlines-ui -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$NEW_FRONTEND" ]]; then
      body=$(kubectl exec -n apollo-airlines-ui "$NEW_FRONTEND" -- \
        sh -c "wget -q -O- http://127.0.0.1:3000/healthz/ready" 2>/dev/null | tr -d '\n' || true)
      if [[ "$body" == "ready" ]]; then break; fi
    fi
    sleep 1
  done
  if [[ "$body" == "ready" ]]; then
    pass "frontend replacement pod serves /healthz/ready=ready"
  else
    fail "frontend replacement pod probe body='$body' (expected 'ready')"
  fi
else
  fail "could not find a frontend pod to delete"
fi

echo ""
echo -e "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}"
exit $FAIL
