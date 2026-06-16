# Stage 2 — research notes

## Envoy Gateway version sweep (recorded)

To pick the right Envoy Gateway version for set 5, I tested the same
minimal Gateway + HTTPRoute workload in fresh kind clusters against 5
versions:

| Version | Service created | HTTP via port-forward |
|---------|-----------------|------------------------|
| v1.2.4  | type=LoadBalancer, port 80 | 200 OK |
| v1.3.0  | type=LoadBalancer, port 80 | 200 OK |
| v1.4.0  | type=LoadBalancer, port 80 | 200 OK |
| v1.4.5  | type=LoadBalancer, port 80 | 200 OK |
| v1.5.0  | type=LoadBalancer, port 80 | 200 OK |

All 5 versions correctly materialize the data-plane listener (via
LDS) and serve traffic. **Chose v1.5.0** for set 5 because it was
already validated in this session and matches the broader v1.x
behavior we'd expect a learner to encounter. Newer versions (v1.6+)
are also valid candidates — the documented Envoy Gateway API hasn't
had a breaking change in the GatewayClass / Gateway / HTTPRoute shape
since v1.2.

## Things that came up that don't matter for the curriculum

### "Only one listener in the bootstrap"

When inspecting the static `--config-yaml` of an Envoy proxy pod, only
one listener shows up (`envoy-gateway-proxy-stats-0.0.0.0-19001`).
The data-plane listener (e.g. `envoy-gateway-proxy-0.0.0.0-10080`) is
pushed dynamically via LDS and is NOT in the static bootstrap. The
controller computes it from the `Gateway.spec.listeners[].port` and
the resolved `HTTPRoute` rules. The xDS stream is bidirectional:
the proxy subscribes to LDS, the controller sends a `Listener` proto
matching `gateway.envoyproxy.io/owning-gateway-name: <name>`. If
`kubectl get svc` shows the auto-created Service is reachable on its
ClusterIP, the listener exists — it just isn't in the static config.

### "EnvoyProxy's `patch` field on `envoyService` doesn't pin a `nodePort`"

The `EnvoyProxy.spec.provider.kubernetes.envoyService` CRD field has
no `nodePort` sub-field. To set a specific `nodePort` (instead of
letting the cluster allocate one), you need a raw `patch.value` block.
This is intentional — the `patch.value` is opaque to the CRD schema,
so it can carry any `Service` field Kubernetes supports. But it also
means the typed `type: NodePort` field is the **only** way to set
the service type via EnvoyProxy; the rest of the service spec has to
go through the patch.

### "MetalLB IP pool range must avoid the kind network gateway"

The default `kind` docker network uses `172.18.0.0/16` for node IPs
(control plane at `.3`, workers at `.2` and `.4` typically). The
MetalLB IP pool in this stage uses `172.18.0.50–172.18.0.100` to
leave a clear gap. If you change the kind network in
`stages/ignition/kind-config.yaml`, update the pool range to match.

### "What about the Traefik dashboard in set 2?"

The dashboard was originally added to set 2 in this session, then
moved out into set 3 in the restage. The dashboard requires Traefik
CRDs (`traefik.io/v1alpha1`) to be installed before the
`IngressRoute` resource can be created. Set 3's `apply.sh` does this
from the upstream `traefik/v3.1` URL. The dashboard also requires
the Traefik controller to be started with `--configFile` and
`--providers.kubernetescrd` — those flags are baked into set 3's
`01-traefik-daemonset.yaml`. The static config (`00-traefik-config.yaml`)
explicitly enables the dashboard and the local API. Set 2 (and set 4)
don't have any of that — they only use the Ingress provider, which
works with CLI-only Traefik.
