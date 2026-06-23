# ECR repos for the 6 Apollo11 services (5 backends + frontend). The backend
# services + frontend are all OCI images; the apply-workloads.sh script
# builds them locally and pushes to ECR.
#
# Each repo:
#   - MUTABLE tags (default; cheap for dev, lets you re-push :latest)
#   - scan-on-push (free basic vulnerability scanning)
#   - force-delete on teardown (otherwise empty repos block destroy)
#
# IAM: the ECR repos are accessible by any IAM principal with
# ecr:GetAuthorizationToken + ecr:BatchGetImage on the repo ARN. The
# node IAM role already has AmazonEC2ContainerRegistryReadOnly for pulls.
# For pushes from CI/laptop, use `aws ecr get-login-password` to refresh
# the Docker config.

locals {
  ecr_repo_names = var.services
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repo_names)

  name                 = "${var.cluster_name}/${each.value}"
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# Lifecycle policy: keep last 10 untagged images + last 10 tagged images.
# Otherwise dev ECR bills can grow unbounded across repeated apply/apply.
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus   = "tagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
