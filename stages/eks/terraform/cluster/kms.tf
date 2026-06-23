module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 3.0"

  description = "KMS key for EKS secrets encryption"
  key_usage   = "ENCRYPT_DECRYPT"

  # Allow the EKS service to use the key for encrypting k8s secrets.
  key_statements = [
    {
      sid    = "EKSClusterUsage"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["eks.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ListGrants",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ]
      resources = ["*"]
    }
  ]

  aliases = ["eks/${var.cluster_name}"]
}

# Compatibility shim: eks_aws module expects module.eks_kms.key_arn.
module "eks_kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 3.0"

  description = "KMS key for EKS secrets encryption (alias target)"
  key_usage   = "ENCRYPT_DECRYPT"
  aliases     = ["eks/${var.cluster_name}"]
}
