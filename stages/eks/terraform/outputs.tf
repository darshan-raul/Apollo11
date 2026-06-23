output "ecr_repository_arns" {
  description = "Map of service name → ECR repo ARN."
  value       = { for k, v in aws_ecr_repository.services : k => v.arn }
}

output "ecr_repository_urls" {
  description = "Map of service name → ECR repo URL (for docker push)."
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "ecr_registry" {
  description = "ECR registry URL (strip /repo suffix). e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com"
  value       = split("/", aws_ecr_repository.services["identity"].repository_url)[0]
}

# ---- cluster ----

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_region" {
  description = "AWS region the cluster is in."
  value       = var.region
}

output "cluster_endpoint" {
  description = "Public EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "One-liner to write kubeconfig. Run this after terraform apply."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

# ---- network ----

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where worker nodes and EBS volumes live)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (where NAT and NLB ENIs live)."
  value       = module.vpc.public_subnets
}

# ---- nlb ----

output "nlb_name" {
  description = "Stable NLB name (matches the EnvoyProxy annotation)."
  value       = "${var.cluster_name}-envoy-nlb"
}

output "nlb_scheme" {
  description = "NLB scheme. Use to decide whether you need a bastion/port-forward."
  value       = var.nlb_scheme
}

# The NLB DNS name and ARN are populated by the AWS provider only after the
# LBC actually creates the NLB. Exposed via `terraform output` once the cluster
# is up. We don't declare them as outputs here because they aren't known at
# apply time — fetch them post-apply with:
#
#   NLB_NAME=$(terraform output -raw nlb_name)
#   NLB_ARN=$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text --region <region>)
#   NLB_DNS=$(aws elbv2 describe-load-balancers --names "$NLB_NAME" --query 'LoadBalancers[0].DNSName' --output text --region <region>)
