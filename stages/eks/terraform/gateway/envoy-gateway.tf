# Apollo11 Envoy Gateway stack on EKS.
#
# This applies the EXACT manifests from stages/stage2/set5-envoy-gateway/k8s/gateway/:
#   - 00-envoy-gateway-install.yaml (~2.9MB; the 00a-gatewayclass.yaml is also
#     part of stage 2 set 5, see the stage 2 apply.sh order)
#   - 00a-gatewayclass.yaml
#   - 00b-envoyproxy.yaml           (PATCHED with LBC annotations, see below)
#   - 01-gateway.yaml
#   - 01a-referencegrant.yaml
#   - 02..07-httproute-*.yaml
#
# The only change vs stage 2 set 5 is the LBC annotations on the EnvoyProxy.
# On EKS, those annotations tell the AWS Load Balancer Controller to provision
# an NLB instead of relying on MetalLB. Everything else (GatewayClass, Gateway,
# HTTPRoutes, ReferenceGrant) is verbatim.

resource "kubectl_manifest" "envoy_gateway_install" {
  yaml_body = file("${path.module}/envoy-gateway-install.yaml")

  # The install.yaml is ~2.9MB. Server-side apply handles the >256KB last-
  # applied-config limit cleanly. Wait for the namespace + CRDs to land
  # before moving on so subsequent applies don't race.
  server_side = true
  force       = true

  depends_on = [
    helm_release.aws_load_balancer_controller,
  ]
}

resource "kubectl_manifest" "gatewayclass" {
  yaml_body = file("${path.module}/gatewayclass.yaml")
  depends_on = [
    kubectl_manifest.envoy_gateway_install,
  ]
}

# The EnvoyProxy in stage 2 set 5 has no annotations because MetalLB is the
# default cloud provider. On EKS we add 5 annotations so the LBC materialises
# the NLB with the right target type, scheme, and stable name.
resource "kubectl_manifest" "envoyproxy_lb_config" {
  yaml_body = templatefile("${path.module}/envoyproxy.yaml.tftpl", {
    nlb_name           = "${var.cluster_name}-envoy-nlb"
    nlb_scheme         = var.nlb_scheme
    nlb_ip_target_type = var.nlb_ip_target_type
  })

  depends_on = [
    kubectl_manifest.gatewayclass,
  ]
}

resource "kubectl_manifest" "gateway" {
  yaml_body = file("${path.module}/gateway.yaml")
  depends_on = [
    kubectl_manifest.envoyproxy_lb_config,
  ]
}

resource "kubectl_manifest" "reference_grant" {
  yaml_body = file("${path.module}/reference-grant.yaml")
  depends_on = [
    kubectl_manifest.gateway,
  ]
}

# Six HTTPRoutes: identity, flight, booking, search, notification, frontend.
locals {
  httproute_files = [
    "httproute-identity.yaml",
    "httproute-flight.yaml",
    "httproute-booking.yaml",
    "httproute-search.yaml",
    "httproute-notification.yaml",
    "httproute-frontend.yaml",
  ]
}

resource "kubectl_manifest" "httproutes" {
  for_each  = toset(local.httproute_files)
  yaml_body = file("${path.module}/${each.value}")

  depends_on = [
    kubectl_manifest.reference_grant,
  ]
}
