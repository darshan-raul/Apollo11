variable "cluster_name" {
  description = "EKS cluster name. Also used as prefix for VPC, ECR repos, IAM roles."
  type        = string
  default     = "apollo11-dev"
}

variable "region" {
  description = "AWS region. EKS, ECR, EBS, NLB are all regional. Pick one close to you for lower latency."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Tag-only. dev | staging | prod. No behavioural difference at the TF level; cost-conscious defaults below already assume dev."
  type        = string
  default     = "dev"
}

variable "azs" {
  description = "Availability Zones to spread the cluster across. NLB requires 2 AZs minimum. Keep this list sorted (first AZ gets the single NAT)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "CIDR for the VPC. /16 gives 65k IPs, plenty for 2 AZs of /22 subnets each."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_public_subnet_cidrs" {
  description = "Public subnet CIDRs. 2 subnets, one per AZ, /22 each = 1024 IPs per AZ. Used for NAT Gateway + NLB ENIs."
  type        = list(string)
  default     = ["10.0.0.0/22", "10.0.4.0/22"]
}

variable "vpc_private_subnet_cidrs" {
  description = "Private subnet CIDRs. 2 subnets, one per AZ. Worker nodes + EBS volumes live here."
  type        = list(string)
  default     = ["10.0.16.0/22", "10.0.20.0/22"]
}

variable "kubernetes_version" {
  description = "K8s version for EKS. 1.31 is the latest EKS-supported as of Jun 2026. Pin to a specific minor so addon versions don't drift unexpectedly."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes. t3.small is the cheapest credible option; t3.medium is more comfortable. Always on-demand-capable in case spot capacity is unavailable."
  type        = string
  default     = "t3.small"
}

variable "node_capacity_type" {
  description = "SPOT (cheap, can be reclaimed) or ON_DEMAND (stable). SPOT saves ~70% but adds reclaim risk during demos."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_group_desired_size" {
  description = "Desired node count. 2 is the minimum for NLB across 2 AZs. Raise to 3-4 if you want HPA headroom."
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Min node count. 1 lets you scale-to-zero for cost savings, but breaks NLB target registration. Keep at 2 for the demo."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Max node count. Used by Cluster Autoscaler if you later enable it."
  type        = number
  default     = 3
}

variable "nlb_scheme" {
  description = "internet-facing for dev (public DNS, hit from your laptop). internal for prod (saves the public IPv4 fees but needs VPN/bastion to reach)."
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.nlb_scheme)
    error_message = "nlb_scheme must be internet-facing or internal."
  }
}

variable "nlb_ip_target_type" {
  description = "ip (route to pod IPs, needs VPC CNI in ip mode — the default on EKS) or instance (route to NodePort, simpler but adds a hop). ip is the LBC default and what Envoy Gateway expects."
  type        = string
  default     = "ip"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_ip_target_type)
    error_message = "nlb_ip_target_type must be ip or instance."
  }
}

variable "single_nat_gateway" {
  description = "true = 1 NAT in AZ-0, route all private subnets through it (saves ~$33/mo). false = 1 NAT per AZ (HA, costs ~$66/mo in NATs alone)."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API server over the public internet. Lock this down to your laptop's IP for safety. 0.0.0.0/0 is fine for dev."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "deletion_protection" {
  description = "EKS deletion protection. MUST be false for `terraform destroy` to succeed in one shot. Flip to true in prod to prevent accidental cluster deletion."
  type        = bool
  default     = false
}

variable "services" {
  description = "Apollo11 services (matches stages/stage3/scripts/apply.sh SERVICES list). One ECR repo per service is created."
  type        = list(string)
  default     = ["identity", "flight", "booking", "search", "notification", "frontend"]
}

variable "ecr_image_tag_mutability" {
  description = "MUTABLE lets you re-push the same tag (good for dev), IMMUTABLE is the prod-safe default."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable ECR scan-on-push (free basic scanning; vulnerability findings show up in the console)."
  type        = bool
  default     = true
}
