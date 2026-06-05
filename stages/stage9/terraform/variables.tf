terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "apollo11"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "apollo11-project"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
