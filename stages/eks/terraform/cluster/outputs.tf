output "cluster_name" {
  description = "EKS cluster name. Use in scripts and kubectl context."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint. Public if endpoint_public_access=true."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN. Use in IAM policies and CloudWatch filters."
  value       = module.eks.cluster_arn
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN. Used for IRSA / Pod Identity."
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_provider_url" {
  description = "OIDC provider URL (without https://). Used for Pod Identity / IRSA trust policies."
  value       = module.eks.oidc_provider
}

output "cluster_security_group_id" {
  description = "Cluster SG ID. Reused for node SG attachment."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Node SG ID. Used by LBC and EBS CSI for inbound rules."
  value       = module.eks.node_security_group_id
}

output "eks_managed_node_groups" {
  description = "Managed node group attributes (ASG name, status, etc.)."
  value       = module.eks.eks_managed_node_groups
}

output "cluster_addons" {
  description = "Addon statuses (vpc-cni, coredns, kube-proxy, etc.)."
  value       = module.eks.cluster_addons
}

output "aws_auth_configmap" {
  description = "Legacy aws-auth ConfigMap (empty map; access entries replace this in EKS 1.30+)."
  value       = module.eks.aws_auth_configmap
}
