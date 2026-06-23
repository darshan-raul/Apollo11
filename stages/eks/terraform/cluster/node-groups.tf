locals {
  node_groups = {
    dev-nodes = {
      name            = "${var.cluster_name}-dev-nodes"
      use_name_prefix = false

      instance_type = var.node_instance_type
      capacity_type = var.node_capacity_type

      desired_size = var.node_group_desired_size
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size

      # Spread across both AZs for HA + NLB target registration.
      subnet_ids = module.vpc.private_subnets

      # AL2023 with the standard EKS-optimized AMI. Containerd runtime.
      ami_type = "AL2023_x86_64_STANDARD"

      # Required for the cluster-autoscaler and k8s events on the nodes.
      enable_efa_support = false

      # k8s labels.
      labels = {
        role        = "worker"
        environment = var.environment
      }

      # Pre-bootstrap the EBS CSI driver dependency (csi-snapshotter etc).
      # Not strictly needed on AL2023 — the EKS-optimized AMI already has
      # the csi-snapshotter / csi-attacher / csi-resizer / csi-livenessprobe
      # sidecar containers. Leaving as a no-op.

      # IAM policy attachments. EKS_CNI_Policy is required for the VPC CNI
      # to assign pod IPs in the VPC. AmazonEC2ContainerRegistryReadOnly
      # lets nodes pull from ECR without an extra IRSA.
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      # Tags required for the cluster-autoscaler + LBC + EBS CSI discovery.
      tags = merge(local.common_tags, {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      })
    }
  }
}
