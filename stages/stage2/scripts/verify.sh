#!/usr/bin/env bash

set -euo pipefail

CONTEXT="${1:-${KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}}"

case "${CONTEXT}" in
  kind-apollo11|kind-apollo11-dev) ;;
  *) printf 'Refusing context %s; Stage 2 only owns kind-apollo11 or kind-apollo11-dev.\n' "${CONTEXT:-<none>}" >&2; exit 2 ;;
esac

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; : $((PASS+=1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; : $((FAIL+=1)); }
step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }

kube() {
  kubectl --context "${CONTEXT}" "$@"
}

step "1. Core Namespaces"
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    pass "Namespace $ns exists"
  else
    fail "Namespace $ns missing"
  fi
done

step "2. Configuration & Secrets"
for ns in apollo-airlines-apps apollo-airlines-ui; do
  if kube get configmap apollo-airlines-config -n "$ns" >/dev/null 2>&1; then
    pass "ConfigMap apollo-airlines-config exists in $ns"
  else
    fail "ConfigMap apollo-airlines-config missing in $ns"
  fi
done

if kube get secret apollo-airlines-secrets -n apollo-airlines-apps >/dev/null 2>&1; then
  pass "Secret apollo-airlines-secrets exists in apollo-airlines-apps"
else
  fail "Secret apollo-airlines-secrets missing in apollo-airlines-apps"
fi

step "3. ServiceAccounts (Strict Token Automount Security)"
EXPECTED_SAS_APPS=(identity-db flight-db booking-db redis identity flight booking search notification init-identity-db init-flight-db init-booking-db)
for sa in "${EXPECTED_SAS_APPS[@]}"; do
  automount=$(kube get sa "$sa" -n apollo-airlines-apps -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "not-found")
  if [[ "$automount" == "false" ]]; then
    pass "SA apollo-airlines-apps/$sa exists (automount=false)"
  else
    fail "SA apollo-airlines-apps/$sa invalid or missing (automount=$automount)"
  fi
done

frontend_automount=$(kube get sa frontend -n apollo-airlines-ui -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "not-found")
if [[ "$frontend_automount" == "false" ]]; then
  pass "SA apollo-airlines-ui/frontend exists (automount=false)"
else
  fail "SA apollo-airlines-ui/frontend invalid or missing (automount=$frontend_automount)"
fi

step "4. Infrastructure Workloads & Seed Jobs"
for comp in identity-db flight-db booking-db redis; do
  ready=$(kube get deployment "$comp" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "${ready:-0}" -ge 1 ]]; then
    pass "Infra deployment apollo-airlines-apps/$comp ready"
  else
    fail "Infra deployment apollo-airlines-apps/$comp not ready"
  fi
done

for job in init-identity-db init-flight-db init-booking-db; do
  complete=$(kube get job "$job" -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
  if [[ "$complete" == "True" ]]; then
    pass "Database init job apollo-airlines-apps/$job completed"
  else
    fail "Database init job apollo-airlines-apps/$job not complete"
  fi
done

step "5. Application Workloads & Services"
for comp in identity flight booking search notification; do
  ready=$(kube get deployment "$comp" -n apollo-airlines-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "${ready:-0}" -ge 1 ]]; then
    pass "App deployment apollo-airlines-apps/$comp ready"
  else
    fail "App deployment apollo-airlines-apps/$comp not ready"
  fi
done

ui_ready=$(kube get deployment frontend -n apollo-airlines-ui -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [[ "${ui_ready:-0}" -ge 1 ]]; then
  pass "UI deployment apollo-airlines-ui/frontend ready"
else
  fail "UI deployment apollo-airlines-ui/frontend not ready"
fi

step "6. Endpoints & EndpointSlice Discovery"
for comp in identity flight booking search notification identity-db flight-db booking-db redis; do
  endpoints=$(kube get endpoints "$comp" -n apollo-airlines-apps -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
  if [[ -n "$endpoints" ]]; then
    pass "Service $comp has ready endpoints ($endpoints)"
  else
    fail "Service $comp has no ready endpoints"
  fi
done

frontend_ep=$(kube get endpoints frontend -n apollo-airlines-ui -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
if [[ -n "$frontend_ep" ]]; then
  pass "Service frontend has ready endpoints ($frontend_ep)"
else
  fail "Service frontend has no ready endpoints"
fi

step "7. Networking Edge Access & Route Verification"

DETECTED_STACK="clusterip"

if kube get gateway apollo-gateway -n apollo-airlines-apps >/dev/null 2>&1; then
  DETECTED_STACK="envoy-gateway"
elif kube get svc traefik -n kube-system >/dev/null 2>&1; then
  svc_type=$(kube get svc traefik -n kube-system -o jsonpath='{.spec.type}')
  if [[ "$svc_type" == "LoadBalancer" ]]; then
    DETECTED_STACK="traefik-metallb"
  else
    DETECTED_STACK="traefik-ingress"
  fi
elif [[ "$(kube get svc identity -n apollo-airlines-apps -o jsonpath='{.spec.type}')" == "NodePort" ]]; then
  DETECTED_STACK="nodeport"
elif kube get pod curl-client -n apollo-airlines-ui >/dev/null 2>&1; then
  DETECTED_STACK="internal-dns"
fi

info "Detected networking architecture: $DETECTED_STACK"

case "$DETECTED_STACK" in
  internal-dns)
    short_dns=$(kube exec -n apollo-airlines-ui curl-client -- nslookup identity 2>&1 || true)
    if echo "$short_dns" | grep -qE "can't find|can't resolve|NXDOMAIN"; then
      pass "Cross-namespace short-name resolution fails as expected"
    else
      fail "Cross-namespace short name unexpectedly resolved: $short_dns"
    fi

    fqdn_dns=$(kube exec -n apollo-airlines-ui curl-client -- nslookup identity.apollo-airlines-apps.svc.cluster.local 2>&1 || true)
    if echo "$fqdn_dns" | grep -q "Address"; then
      pass "Cross-namespace FQDN resolves via CoreDNS"
    else
      fail "Cross-namespace FQDN resolution failed: $fqdn_dns"
    fi

    resp=$(kube exec -n apollo-airlines-ui curl-client -- curl -s http://identity.apollo-airlines-apps.svc.cluster.local:8080/healthz 2>&1 || true)
    if echo "$resp" | grep -q "ok"; then
      pass "Internal HTTP request across namespaces succeeds"
    else
      fail "Internal HTTP call failed: $resp"
    fi
    ;;

  nodeport)
    for port_info in "30080:frontend:frontend" "30081:flight:healthz" "30082:booking:healthz" "30083:identity:healthz" "30084:search:healthz"; do
      IFS=":" read -r port name path <<< "$port_info"
      code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:${port}/${path}" 2>/dev/null || echo "000")
      if [[ "$code" == "200" ]]; then
        pass "NodePort $port ($name) accessible from host (HTTP $code)"
      else
        fail "NodePort $port ($name) unreachable (HTTP $code)"
      fi
    done
    ;;

  traefik-ingress)
    traefik_ready=$(kube get ds traefik -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
    if [[ "${traefik_ready:-0}" -ge 1 ]]; then
      pass "Traefik DaemonSet ready ($traefik_ready pods)"
    else
      fail "Traefik DaemonSet not ready"
    fi

    for host in "identity.apollo.local" "flight.apollo.local" "booking.apollo.local" "search.apollo.local"; do
      code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" --connect-timeout 2 "http://localhost:30080/healthz" 2>/dev/null || echo "000")
      if [[ "$code" == "200" ]]; then
        pass "Traefik host routing to $host on :30080 (HTTP $code)"
      else
        fail "Traefik host routing to $host failed (HTTP $code)"
      fi
    done

    tls_subj=$(curl -k -v --resolve "identity.apollo.local:30443:127.0.0.1" "https://identity.apollo.local:30443/healthz" 2>&1 | grep "subject:" || echo "")
    if echo "$tls_subj" | grep -q "*.apollo.local"; then
      pass "Traefik TLS termination serves *.apollo.local certificate on :30443"
    else
      fail "Traefik TLS certificate mismatch: $tls_subj"
    fi
    ;;

  traefik-metallb)
    lb_ip=$(kube get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$lb_ip" ]]; then
      pass "Traefik Service assigned LoadBalancer IP: $lb_ip"
    else
      fail "Traefik Service missing LoadBalancer IP"
    fi

    if [[ -n "$lb_ip" ]]; then
      for host in "identity.apollo.local" "flight.apollo.local"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" --connect-timeout 2 "http://${lb_ip}/healthz" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
          pass "MetalLB LoadBalancer direct port 80 routing to $host (HTTP $code)"
        else
          fail "MetalLB LoadBalancer routing to $host failed (HTTP $code)"
        fi
      done
    fi
    ;;

  envoy-gateway)
    gc_status=$(kube get gatewayclass eg -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
    if [[ "$gc_status" == "True" ]]; then
      pass "GatewayClass eg accepted by Envoy Gateway controller"
    else
      fail "GatewayClass eg not accepted"
    fi

    gw_prog=$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "False")
    gw_acc=$(kube get gateway apollo-gateway -n apollo-airlines-apps -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
    if [[ "$gw_prog" == "True" && "$gw_acc" == "True" ]]; then
      pass "Gateway apollo-gateway is Accepted and Programmed"
    else
      fail "Gateway apollo-gateway status invalid (Accepted=$gw_acc, Programmed=$gw_prog)"
    fi

    for route in identity flight booking search notification; do
      route_acc=$(kube get httproute "$route" -n apollo-airlines-apps -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
      if [[ "$route_acc" =~ "True" ]]; then
        pass "HTTPRoute apollo-airlines-apps/$route accepted"
      else
        fail "HTTPRoute apollo-airlines-apps/$route not accepted"
      fi
    done

    frontend_route_acc=$(kube get httproute frontend -n apollo-airlines-ui -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "False")
    if [[ "$frontend_route_acc" =~ "True" ]]; then
      pass "HTTPRoute apollo-airlines-ui/frontend accepted"
    else
      fail "HTTPRoute apollo-airlines-ui/frontend not accepted"
    fi

    eg_ip=$(kube get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$eg_ip" ]]; then
      pass "Envoy Proxy assigned MetalLB LoadBalancer IP: $eg_ip"
    else
      fail "Envoy Proxy missing LoadBalancer IP"
    fi

    if [[ -n "$eg_ip" ]]; then
      for host in "identity.apollo.local" "flight.apollo.local" "booking.apollo.local" "search.apollo.local"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" --connect-timeout 2 "http://${eg_ip}/healthz" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
          pass "Envoy Gateway HTTPRoute to $host returned HTTP $code"
        else
          fail "Envoy Gateway HTTPRoute to $host failed (HTTP $code)"
        fi
      done

      fe_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" --connect-timeout 2 "http://${eg_ip}/" 2>/dev/null || echo "000")
      if [[ "$fe_code" == "200" ]]; then
        pass "Envoy Gateway cross-namespace HTTPRoute to frontend returned HTTP $fe_code"
      else
        fail "Envoy Gateway frontend route failed (HTTP $fe_code)"
      fi

      for host in "identity.apollo.local" "booking.apollo.local"; do
        https_code=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $host" --connect-timeout 2 "https://${eg_ip}/healthz" 2>/dev/null || echo "000")
        if [[ "$https_code" == "200" ]]; then
          pass "Envoy Gateway HTTPS listener (port 443 TLS) to $host returned HTTP $https_code"
        else
          fail "Envoy Gateway HTTPS listener to $host failed (HTTP $https_code)"
        fi
      done

      fe_https_code=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: frontend.apollo.local" --connect-timeout 2 "https://${eg_ip}/" 2>/dev/null || echo "000")
      if [[ "$fe_https_code" == "200" ]]; then
        pass "Envoy Gateway HTTPS listener (port 443 TLS) to frontend returned HTTP $fe_https_code"
      else
        fail "Envoy Gateway HTTPS listener to frontend failed (HTTP $fe_https_code)"
      fi
    fi
    ;;
esac

step "8. End-to-End Application & Auth Verification"
TOKEN=""
if [[ "$DETECTED_STACK" == "envoy-gateway" && -n "${eg_ip:-}" ]]; then
  login_resp=$(curl -s -X POST "http://${eg_ip}/api/users/login" \
    -H "Host: identity.apollo.local" \
    -H "Content-Type: application/json" \
    -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || echo "")
elif [[ "$DETECTED_STACK" == "nodeport" ]]; then
  login_resp=$(curl -s -X POST "http://localhost:30083/api/users/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || echo "")
else
  login_resp=$(kube exec -n apollo-airlines-ui deployment/frontend -- curl -s -X POST "http://identity.apollo-airlines-apps.svc.cluster.local:8080/api/users/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"passenger@apolloairlines.com","password":"pass123"}' 2>/dev/null || echo "")
fi

TOKEN=$(echo "$login_resp" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "")
if [[ -n "$TOKEN" ]]; then
  pass "Passenger authentication succeeded and returned JWT"
else
  fail "Passenger authentication failed: $login_resp"
fi

if [[ -n "$TOKEN" ]]; then
  if [[ "$DETECTED_STACK" == "envoy-gateway" && -n "${eg_ip:-}" ]]; then
    flights_resp=$(curl -s -H "Host: flight.apollo.local" "http://${eg_ip}/api/flights" 2>/dev/null || echo "")
  elif [[ "$DETECTED_STACK" == "nodeport" ]]; then
    flights_resp=$(curl -s "http://localhost:30081/api/flights" 2>/dev/null || echo "")
  else
    flights_resp=$(kube exec -n apollo-airlines-ui deployment/frontend -- curl -s "http://flight.apollo-airlines-apps.svc.cluster.local:8081/api/flights" 2>/dev/null || echo "")
  fi

  if echo "$flights_resp" | grep -q "flights"; then
    pass "Flight inventory query returned flights from flight-db"
  else
    fail "Flight inventory query failed: $flights_resp"
  fi
fi

step "Verification Summary"
echo -e "  Total Passed: ${GREEN}${PASS}${NC}"
echo -e "  Total Failed: ${RED}${FAIL}${NC}"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo -e "\n${GREEN}Stage 2 verification succeeded with 0 failures.${NC}\n"
