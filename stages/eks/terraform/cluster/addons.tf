locals {
  cluster_addons = {
    # VPC CNI: assigns pod IPs from the VPC. Required for the LBC's
    # `nlb-ip-target-type: ip` annotation. Must be installed before nodes start.
    vpc-cni = {
      most_recent          = true
      before_compute       = true
      service_account_role_arn = module.vpc_cni_role.iam_role_arn

      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI           = "true"
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    # CoreDNS: cluster DNS. Installed by default but pinned here for version control.
    coredns = {
      most_recent = true
    }

    # kube-proxy: required for Service routing.
    kube-proxy = {
      most_recent = true
    }

    # Pod Identity agent: replaces IRSA for the addons. Newer and simpler
    # than the OIDC + trust policy dance. Must be installed before nodes start.
    eks-pod-identity-agent = {
      most_recent              = true
      before_compute           = true
      service_account_role_arn = module.pod_identity_agent_role.iam_role_arn
    }

    # EBS CSI driver: provisions EBS volumes for the StatefulSets' PVCs.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_role.iam_role_arn
    }

    # AWS Load Balancer Controller: provisions the NLB for Envoy Gateway.
    aws-load-balancer-controller = {
      most_recent              = true
      service_account_role_arn = module.lbc_role.iam_role_arn
    }
  }
}
