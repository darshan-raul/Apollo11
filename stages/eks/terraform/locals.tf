locals {
  name = var.cluster_name

  common_tags = {
    Project     = "Apollo11"
    Environment = var.environment
    Stage       = "eks"
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
  }

  vpc_name = "${var.cluster_name}-vpc"
}
