# --------------------------------------------------------------------------------
# ALB Security Group Rules
# --------------------------------------------------------------------------------

# Allow inbound HTTPS from CloudFront
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group_rule" "alb_from_cloudfront" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = var.alb_security_group_id
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  description       = "HTTPS from CloudFront"
}

# Allow outbound to ECS
resource "aws_security_group_rule" "alb_to_ecs" {
  type                     = "egress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = var.alb_security_group_id
  source_security_group_id = var.ecs_security_group_id
  description              = "To ECS tasks"
}
