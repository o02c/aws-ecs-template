# --------------------------------------------------------------------------------
# Aurora PostgreSQL Cluster (Serverless v2)
# --------------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.4"
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [var.db_security_group_id]
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.project_name}-${var.environment}-aurora-final"

  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora"
  }
}

# --------------------------------------------------------------------------------
# Aurora Instances
# --------------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  for_each = var.db_instances

  identifier              = "${var.project_name}-${var.environment}-aurora-${each.key}"
  cluster_identifier      = aws_rds_cluster.this.id
  instance_class          = "db.serverless"
  engine                  = aws_rds_cluster.this.engine
  engine_version          = aws_rds_cluster.this.engine_version
  db_parameter_group_name = aws_db_parameter_group.this.name

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Cluster Parameter Group
# --------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-aurora-cluster"
  family = "aurora-postgresql16"

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-cluster"
  }
}

# --------------------------------------------------------------------------------
# DB Parameter Group
# --------------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-aurora-instance"
  family = "aurora-postgresql16"

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-instance"
  }
}

# --------------------------------------------------------------------------------
# Subnet Group
# --------------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-aurora"
  subnet_ids = values(var.private_subnet_ids)

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora"
  }
}
