# --------------------------------------------------------------------------------
# Internal Application Load Balancer
# --------------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.project_name}-${var.environment}-${var.lane}"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = values(var.private_subnet_ids)
  idle_timeout       = var.idle_timeout_seconds

  access_logs {
    bucket  = var.log_bucket_id
    prefix  = var.log_prefix
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}

# --------------------------------------------------------------------------------
# Target Group
# --------------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  name = "${var.project_name}-${var.environment}-${var.lane}"
  # target_type = ip registers each ECS task on its own container port, so this
  # attribute is only a nominal default and is not used for routing/health checks
  # (those follow the registered traffic-port = container_port). Pinned to 80 and
  # kept independent of var.container_port: changing a live TG's port forces
  # replacement, which fails while the running ECS service still holds the group.
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.target_group.deregistration_delay_seconds

  health_check {
    path                = var.target_group.health_check.path
    healthy_threshold   = var.target_group.health_check.healthy_threshold
    unhealthy_threshold = var.target_group.health_check.unhealthy_threshold
    timeout             = var.target_group.health_check.timeout_seconds
    interval            = var.target_group.health_check.interval_seconds
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}

# --------------------------------------------------------------------------------
# HTTPS Listener
# --------------------------------------------------------------------------------

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
