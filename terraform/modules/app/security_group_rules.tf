# --------------------------------------------------------------------------------
# ECS Security Group Rules
# --------------------------------------------------------------------------------

# Allow inbound from ALB (per-lane)
resource "aws_security_group_rule" "ecs_from_alb" {
  for_each = var.alb_security_group_ids

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = var.ecs_security_group_id
  source_security_group_id = each.value
  description              = "From ${each.key} ALB"
}

# Allow outbound to DB
resource "aws_security_group_rule" "ecs_to_db" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.ecs_security_group_id
  source_security_group_id = var.db_security_group_id
  description              = "To Aurora PostgreSQL"
}

# Allow outbound HTTPS to VPC endpoints
resource "aws_security_group_rule" "ecs_to_vpce" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.ecs_security_group_id
  source_security_group_id = var.vpce_security_group_id
  description              = "HTTPS to VPC endpoints"
}

# Allow VPC endpoints inbound from ECS
resource "aws_security_group_rule" "vpce_from_ecs" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.vpce_security_group_id
  source_security_group_id = var.ecs_security_group_id
  description              = "HTTPS from ECS tasks"
}
