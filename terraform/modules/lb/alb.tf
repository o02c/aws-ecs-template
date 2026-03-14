# --------------------------------------------------------------------------------
# Internal Application Load Balancer
# --------------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.project_name}-${var.environment}-${var.lane}"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = values(var.private_subnet_ids)

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}

# --------------------------------------------------------------------------------
# Target Group
# --------------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  name        = "${var.project_name}-${var.environment}-${var.lane}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
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
