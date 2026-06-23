# IAM roles + Pod Identity associations for the 3rd-party addons.
#
# We use EKS Pod Identity (via aws_eks_pod_identity_association) instead of
# the older IRSA pattern. Pod Identity is the AWS-recommended path going
# forward and is supported by all EKS versions on 1.30+.
#
# Each role trusts the cluster's OIDC provider (via the Pod Identity agent),
# restricted to a specific ServiceAccount in a specific namespace.

data "aws_partition" "current" {}

# ------------------------------------------------------------------ EBS CSI

module "ebs_csi_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 5.0"

  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = module.ebs_csi_role.iam_role_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = module.ebs_csi_role.iam_role_arn
}

# ------------------------------------------------------------------ LBC

module "lbc_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 5.0"

  name = "${var.cluster_name}-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = module.lbc_role.iam_role_name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.lbc_role.iam_role_arn
}

# ------------------------------------------------------------------ VPC CNI

module "vpc_cni_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = module.vpc_cni_role.iam_role_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = module.vpc_cni_role.iam_role_arn
}

# ------------------------------------------------------------------ Pod Identity agent

module "pod_identity_agent_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 5.0"

  name = "${var.cluster_name}-pod-identity-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "pod_identity_agent" {
  role       = module.pod_identity_agent_role.iam_role_name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSPodIdentityAgentPolicy"
}

resource "aws_eks_pod_identity_association" "pod_identity_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "eks-pod-identity-agent"
  role_arn        = module.pod_identity_agent_role.iam_role_arn
}
