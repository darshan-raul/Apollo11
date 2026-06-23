module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Networking: control plane + nodes share the private subnets. The API
  # endpoint is exposed publicly for kubectl access; the kubelet-to-apiserver
  # hop stays inside the VPC via endpoint_private_access.
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Public API endpoint for kubectl from your laptop. Lock down to your
  # laptop's CIDR in variables.tf for safety.
  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = var.cluster_endpoint_public_access_cidrs

  # Encryption-at-rest for k8s secrets using a KMS key the module creates.
  # Adds $1/month — keep it.
  encryption_config = {
    provider_key_arn = module.eks_kms.key_arn
    resources        = ["secrets"]
  }

  # Cluster-level SG rules. Allow your IP to talk to the API on 443.
  cluster_security_group_additional_rules = {
    api_https_from_cidr = {
      description = "K8s API server HTTPS from operator CIDR"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = var.cluster_endpoint_public_access_cidrs
    }
  }

  # Replace the legacy aws-auth ConfigMap. Your IAM principal gets cluster-admin.
  # To add more users later, add more entries to access_entries.
  access_entries = {
    admin = {
      principal_arn = data.aws_caller_identity.current.arn
      type          = "STANDARD"

      policy_associations = {
        cluster-admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/cluster-admin"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Make destroy one-shot work.
  deletion_protection = var.deletion_protection

  # The node groups live in node-groups.tf. Addons in addons.tf. The module's
  # built-in addons block lets us pin versions cleanly.
  eks_managed_node_groups = local.node_groups

  # The cluster addons. We let the module create the aws_eks_addon resources
  # and pass Pod Identity associations for the ones that need them.
  cluster_addons = local.cluster_addons

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
