---
title: "Local HTTPS, TLS Certificates & Gateway Routing"
description: "Shared guide for local wildcard TLS certificates, Secret ownership across Stages 2–7, local DNS, and verification."
---

# Local HTTPS, TLS Certificates & Gateway Routing

From **Stage 2 Substage 5 (Envoy Gateway)** onward (and in **Stage 2 Substage 3** with Traefik), Apollo Airlines serves the frontend and APIs over HTTPS using a wildcard certificate for `*.apollo.local` and `apollo.local`.

> On **macOS** or **Windows (WSL2 / Docker Desktop)** where MetalLB IPs (`172.18.0.50`) are inside the VM bridge, use the [port-forward / `cloud-provider-kind` fallback](../README.md#macos-and-windows-wsl2--docker-desktop-networking-fallback) alongside this guide.

---

## 1. TLS Secret Ownership Across Stages

Secret names and namespaces depend on the ingress/gateway controller and stage packaging:

| Stage Scope | Controller | Secret Name | Namespace(s) | Ownership |
|---|---|---|---|---|
| **Stage 2 Substage 3** (`03-traefik-ingress-tls`) | Traefik Ingress | `apollo-tls-secret` | `apollo-airlines-apps` **and** `apollo-airlines-ui` | Created by `generate-certs.sh` |
| **Stage 2 Substage 5 – Stage 4** | Envoy Gateway | `apollo-tls-secret` | `apollo-airlines-apps` | Created by `generate-certs.sh` |
| **Stages 5–7** (`helm` / `kustomize`) | Envoy Gateway | `apollo-edge-tls` | `apollo-airlines-apps` | Runtime-generated outside Helm/Kustomize release ownership (`generate-certs.sh`) |
| **Stage 5 Optional Argo CD (Substage 5B)** | Envoy Gateway | `apollo-edge-tls` | `apollo-airlines-{dev,staging,prod}-{apps,ui}` | Pre-created per tenant by `argocd/scripts/bootstrap.sh` |

**Frontend build-time URL boundary:** The frontend container bakes `VITE_IDENTITY_URL`, `VITE_FLIGHT_URL`, `VITE_BOOKING_URL`, and `VITE_SEARCH_URL` into its NGINX bundle during `docker build` (via `build-images.sh` / `values.yaml`). Stage 2 Substages 1–4 bake `http://`; Stage 2 Substage 5 through Stage 7 bake `https://`. Always rebuild the `frontend` image when switching between HTTP and HTTPS stages.

---

## 2. Generating Certificates (`generate-certs.sh` or Optional `mkcert`)

### Standard Repo Script (OpenSSL Self-Signed Wildcard)

Every HTTPS stage provides `scripts/generate-certs.sh`:

```bash
export KUBE_CONTEXT=kind-apollo11   # or kind-apollo11-dev
bash scripts/generate-certs.sh      # pass --rotate to replace an existing Secret
```

Behavior:
- **Context safety guard:** Refuses to run unless `KUBE_CONTEXT` is `kind-apollo11` or `kind-apollo11-dev`.
- **Idempotent:** Keeps any existing Secret intact unless `--rotate` is passed.
- **Certificate generated:**
  ```bash
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj '/CN=*.apollo.local' \
    -addext 'subjectAltName=DNS:*.apollo.local,DNS:apollo.local'
  ```

### Optional `mkcert` Local CA (Browser Trust Without Warnings)

If you want your OS and browser to trust `*.apollo.local` automatically without self-signed warnings:

```bash
mkcert -install
mkcert -cert-file /tmp/apollo-mkcert.crt -key-file /tmp/apollo-mkcert.key '*.apollo.local' apollo.local

# Use apollo-tls-secret (Stages 2–4) or apollo-edge-tls (Stages 5–7):
kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps create secret tls apollo-edge-tls \
  --cert=/tmp/apollo-mkcert.crt --key=/tmp/apollo-mkcert.key --dry-run=client -o yaml | \
  kubectl --context "$KUBE_CONTEXT" apply -f -
```

For Stage 2 Substage 3 (Traefik), also apply `apollo-tls-secret` into `apollo-airlines-ui`. Never commit `.key` files to Git.

---

## 3. Hostnames & Local DNS (`/etc/hosts` vs. `curl --resolve`)

All Apollo Airlines edge `HTTPRoute`s share the `*.apollo.local` wildcard certificate:

- `frontend.apollo.local`
- `identity.apollo.local`
- `flight.apollo.local`
- `booking.apollo.local`
- `search.apollo.local`
- `notification.apollo.local` (route exists on the Gateway; browser UI calls the four APIs above)
- `grafana.apollo.local` (**Stage 6+**, cross-namespace `HTTPRoute` in `apollo-observability` attaching via `allowedRoutes.namespaces.from: All`)

MetalLB allocates a `LoadBalancer` IP from `172.18.0.50-172.18.0.100` (typically `172.18.0.50`) to the Envoy Gateway Service.

- **Terminal tests:** Use `curl --resolve "<host>:443:${gateway_ip}"` (no `/etc/hosts` edit required).
- **Browser access (Linux):** Add `<gateway_ip> frontend.apollo.local identity.apollo.local flight.apollo.local booking.apollo.local search.apollo.local grafana.apollo.local` to `/etc/hosts`.

---

## 4. Verification, Browser Checks & Break / Recover

### Extract the Cluster Certificate & Gateway IP

```bash
export KUBE_CONTEXT="${KUBE_CONTEXT:-kind-apollo11}"
# Use apollo-tls-secret in Stages 2–4, or apollo-edge-tls in Stages 5–7
SECRET_NAME=apollo-edge-tls

kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps get secret "$SECRET_NAME" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/apollo-ca.crt

gateway_ip=$(kubectl --context "$KUBE_CONTEXT" -n envoy-gateway-system get service \
  -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
```

### Positive & Negative TLS Checks

```bash
# Positive check: verifies both certificate chain and SAN hostname match
# (Avoid curl -k for verification; -k disables trust and is diagnostic-only.)
curl --cacert /tmp/apollo-ca.crt \
  --resolve "identity.apollo.local:443:${gateway_ip}" \
  https://identity.apollo.local/healthz

# Negative check: untrusted hostname must fail TLS hostname verification (exit code 60)
curl -sS --cacert /tmp/apollo-ca.crt \
  --resolve "untrusted.apollo.invalid:443:${gateway_ip}" \
  https://untrusted.apollo.invalid/healthz
```

In your browser at `https://frontend.apollo.local`, open DevTools **Network** and confirm every API request (`identity`, `flight`, `booking`, `search`) uses `https://` with zero mixed-content errors.

### Break & Recover

- **Break:** Delete the TLS Secret (`kubectl --context "$KUBE_CONTEXT" -n apollo-airlines-apps delete secret "$SECRET_NAME"`). The `:443` HTTPS listener stops serving valid TLS while the `:80` HTTP listener remains up.
  - **Traefik Substage 3 caveat:** Traefik pools Secrets across namespaces; to break Substage 3 TLS cleanly, delete `apollo-tls-secret` in **both** `apollo-airlines-apps` and `apollo-airlines-ui`.
- **Recover:** Re-run `bash scripts/generate-certs.sh`, re-extract `/tmp/apollo-ca.crt`, and re-run the `curl --cacert` check above.
