output "vpc_id" {
  description = "VPC ID. Pass to other modules that need to peer or share resources."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR. Use in SG rules and k8s NetworkPolicies."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs. NLB ENIs and NAT Gateway live here."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs. Worker nodes, EBS volumes, pod IPs live here. EKS module takes these as input."
  value       = module.vpc.private_subnets
}

output "nat_public_ips" {
  description = "EIPs attached to the NAT Gateway(s). Useful for debugging egress."
  value       = module.vpc.nat_public_ips
}
