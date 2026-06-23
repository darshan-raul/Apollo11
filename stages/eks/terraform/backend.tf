# Local state backend. State file ends up ~5-10 MB because of the EKS module's
# verbosity (VPC + IAM + cluster + node groups + addons + Pod Identity + KMS).
# Manageable on a single dev machine. To share with another dev or survive
# `rm -rf` of your devbox, swap to S3 + DynamoDB lock:
#
#   terraform {
#     backend "s3" {
#       bucket         = "apollo11-tfstate"
#       key            = "eks/terraform.tfstate"
#       region         = "us-east-1"
#       dynamodb_table = "apollo11-tflock"
#       encrypt        = true
#     }
#   }
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
