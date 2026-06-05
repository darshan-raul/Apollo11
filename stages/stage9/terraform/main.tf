module "vpc" {
  source = "./modules/vpc"

  providers = {
    aws = aws
  }

  cluster_name = var.cluster_name
  environment  = var.environment
}

module "eks" {
  source = "./modules/eks"

  providers = {
    aws = aws
  }

  cluster_name    = var.cluster_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  node_group_name = "${var.cluster_name}-node-group"
}

module "gke" {
  source = "./modules/gke"

  providers = {
    google = google
  }

  cluster_name = var.cluster_name
  environment  = var.environment
  vpc_id       = module.vpc.gke_vpc_id
  subnet_id    = module.vpc.gke_subnet_id
}

module "ingress" {
  source = "./modules/ingress"

  providers = {
    aws    = aws
    google = google
  }

  cluster_name   = var.cluster_name
  environment    = var.environment
  eks_cluster_id = module.eks.cluster_id
  gke_cluster_id = module.gke.cluster_id
}
