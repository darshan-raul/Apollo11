resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  tags = {
    Name        = "${var.cluster_name}-alb-sg"
    Environment = var.environment
  }
}

resource "aws_lb" "main" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.alb.id]
  subnets            = data.terraform_remote_state.vpc.outputs.public_subnet_ids

  tags = {
    Name        = "${var.cluster_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "frontend" {
  name     = "${var.cluster_name}-frontend-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.vpc.outputs.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.cluster_name}-frontend-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name        = "${var.cluster_name}-frontend-listener"
    Environment = var.environment
  }
}

data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "${path.module}/../vpc/terraform.tfstate"
  }
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}
