# --------------------------------------------------------------------------------
# ALB Security Group Rules
# --------------------------------------------------------------------------------

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
