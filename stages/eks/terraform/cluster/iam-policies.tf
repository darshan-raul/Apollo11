resource "aws_iam_policy" "lbc" {
  name        = "${var.cluster_name}-lbc"
  description = "AWS Load Balancer Controller policy for ${var.cluster_name}"

  policy = file("${path.module}/policies/lbc-policy.json")

  tags = local.common_tags
}
