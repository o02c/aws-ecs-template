# --------------------------------------------------------------------------------
# DB Security Group Rules
# --------------------------------------------------------------------------------

# Allow inbound PostgreSQL from ECS
resource "aws_security_group_rule" "db_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = var.ecs_security_group_id
  description              = "PostgreSQL from ECS"
}
