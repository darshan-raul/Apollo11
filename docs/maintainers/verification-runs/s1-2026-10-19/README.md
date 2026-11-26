# S1 live lifecycle — 2026-10-19

Commit `1ac5c66` plus uncommitted teardown fixes. Fresh `kind-apollo11` cluster
(3 nodes, `stages/ignition/kind-config.yaml`), Kubernetes server v1.37.0,
Docker 29.7.2. Each run: apply, verify, (break/recover), teardown, residue check.

| Run | Verify result | Break / recover | Teardown residue |
|---|---|---|---|
| Stage 2 sub 5 (Envoy Gateway) | 61/61 (docs said 57) | frontend HTTPRoute port 9999: `ResolvedRefs=False (PortNotFound)`, HTTP 500; restored to 3000: HTTP 200 | none after fix |
| Stage 2 sub 3 (Traefik + TLS) | 49/49 | not run | none |
| Stage 2 sub 4 (MetalLB) | 46/46 | not run | none |
| Stage 3 | 69/69 (docs said 68) | identity-db row survived pod delete (2 → 3 → 3, test row removed) | none after fix |
| Stage 4 | 149/149 | booking eviction 1 allowed, 2nd rejected `TooManyRequests`; gateway 200 throughout; rollout and PDB recovered | none |

Follow-up runs (same day):

| Run | Result |
|---|---|
| Stage 2 sub 3 break: delete `apollo-tls-secret` | Deleting only the apps copy still served `*.apollo.local` (the ui copy is the same wildcard, Traefik logged the error but kept serving). Deleting both gave `TRAEFIK DEFAULT CERT`; `generate-certs.sh` restored `*.apollo.local`. README corrected to delete both |
| Stage 2 sub 4 break: delete IPAddressPool, recreate traefik Service | `EXTERNAL-IP <pending>`; restoring the pool gave `172.18.0.50` and `{"status":"ok"}` (README expected body corrected) |
| Stage 2 sub 4 → 5 in-place upgrade, re-verify after teardown fix | 61/61 |
| Stage 2 sub 5 cert break | Gateway `https` listener `ResolvedRefs=False (InvalidCertificateRef)`, HTTPS no response, HTTP 200; regenerated cert: listener Programmed, `verify-tls.sh` passed |
| Stage 3 (rebuilt images) apply + verify | 69/69; cert break/recover as above, `verify-tls.sh` passed; teardown clean |
| Stage 4 (rebuilt images) apply + verify | 149/149; cert break/recover as above, `verify-tls.sh` passed; teardown clean |

Findings:
- Stage 2, 3 and 4 `teardown.sh` left cluster-scoped residue (26 CRDs, MetalLB/Envoy
  ClusterRoles, ClusterRoleBindings, webhook configurations) after deleting namespaces.
  Fixed in all three scripts; they now delete these objects and fail if Gateway API,
  Envoy Gateway or MetalLB CRDs remain (including `gateway.networking.x-k8s.io`).
- `apply.sh --skip-build` on Stage 4 after Stage 2/3 left the old images in kind
  (shared `apollo11/*:latest` tags), so pods lacked `/healthz/startup` and crash-looped.
  Stage 4 needs a fresh build.
- All planned S1 break experiments are now covered.
