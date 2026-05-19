# --------------------------------------------------------------------------------
# db_sql Lambda → DB: PostgreSQL ingress
# --------------------------------------------------------------------------------

resource "aws_security_group_rule" "db_from_db_sql" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = var.db_sql_security_group_id
  description              = "PostgreSQL from db_sql Lambda"
}

# --------------------------------------------------------------------------------
# db_sql Lambda → outbound
# --------------------------------------------------------------------------------
# Follows the ECS module pattern: explicit egress per destination, no 0.0.0.0/0.

resource "aws_security_group_rule" "db_sql_to_db" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.db_sql_security_group_id
  source_security_group_id = var.db_security_group_id
  description              = "PostgreSQL to Aurora"
}

# Secrets Manager (DDL) + RDS API (DML, generate_db_auth_token) live behind
# interface endpoints in the shared VPC, reachable via Transit Gateway.
resource "aws_security_group_rule" "db_sql_to_vpce" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = var.db_sql_security_group_id
  cidr_blocks       = var.shared_private_subnet_cidrs
  description       = "HTTPS to shared VPC endpoints via TGW (Secrets Manager, RDS)"
}

# SQL file reads from the bucket flow through the in-VPC S3 gateway endpoint.
resource "aws_security_group_rule" "db_sql_to_s3" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = var.db_sql_security_group_id
  prefix_list_ids   = [var.s3_prefix_list_id]
  description       = "HTTPS to S3 via gateway endpoint"
}
