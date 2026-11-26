---
title: "G1c — Stage 2 substages 1 and 2 re-verification (2026-10-24)"
description: "Live lifecycle evidence for Stage 2 substages 1 (ClusterIP/DNS) and 2 (NodePort) on Apollo11 97232fb."
---

# G1c — Stage 2 substages 1 and 2 (2026-10-24)

Code: Apollo11 `97232fb` (Stage 2 untouched by the parallel G17 work). Cluster:
the fresh three-node `kind-apollo11` from G1b, Kubernetes v1.37.0.

| Substage | Apply | Verify | Break / recover | Log |
|---|---|---|---|---|
| 1 ClusterIP & DNS | `apply.sh --substage 1` (images built), rc 0 | **46 passed, 0 failed** | Identity selector → `identity-broken`: EndpointSlice empty, FQDN curl from `curl-client` fails (000). Restored: 2 endpoints, HTTP 200 | `sub1-*.log` |
| 2 NodePort | `apply.sh --substage 2 --skip-build`, rc 0 | **48 passed, 0 failed** | Identity `targetPort: 9999`: `localhost:30083` fails (000). Restored to 8080: HTTP 200 | `sub2-*.log` |

Teardown: `teardown.sh kind-apollo11` left 0 Apollo namespaces, 0
Gateway/Envoy/MetalLB CRDs and 0 matching ClusterRoles (`residue.log`). The
cluster was kept.

## Findings fed to G18

- **Browser UI in substage 2 cannot reach the APIs.** The served bundle bakes
  `http://{identity,flight,booking,search}.apollo.local` with no port
  (`sub2-frontend-bundle.log`). On this host those names resolve to
  `172.18.0.50` (MetalLB), where nothing listens until substage 4, so login and
  search from the browser fail. This was inferred from code in the audit and is
  now observed.
- **Inconsistent context flag.** `teardown.sh` accepts the context only as a
  positional argument; `teardown.sh --context kind-apollo11` is refused with
  "Refusing context --context" (safe, but inconsistent with `apply.sh`). The
  first line of `teardown.log` shows the refusal; the positional call then ran.
