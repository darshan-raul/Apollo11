variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "eks_cluster_id" {
  description = "EKS cluster ID"
  type        = string
}

variable "gke_cluster_id" {
  description = "GKE cluster ID"
  type        = string
}
