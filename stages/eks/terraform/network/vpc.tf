module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.vpc_name
  cidr = var.vpc_cidr

  azs              = var.azs
  public_subnets   = var.vpc_public_subnet_cidrs
  private_subnets  = var.vpc_private_subnet_cidrs

  # Public subnets host: NAT Gateway, NLB ENIs, AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private subnets host: worker nodes, EBS volumes, pod IPs.
  # The cluster-autoscaler / LBC / EBS CSI driver discover subnets via these tags.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    # EKS auto-discovers subnets via cluster name tag (used by LBC + EBS CSI).
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Cost-down choice for dev. AZ-1 nodes pay cross-AZ data transfer on
  # NAT-routed egress (~$0.01/GB). For prod flip to per-AZ NATs.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Reuse EIPs across destroys/creates to avoid the $0.005/hr "idle public IPv4" fee.
  reuse_nat_ips = true

  # map_public_ip_on_launch defaults to true on public subnets. We leave it
  # true (public subnets are intentionally public — NAT GW and NLB ENIs go here).
}
