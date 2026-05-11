# --------------------------------------------------------------------------------
# Aurora PostgreSQL Cluster (provisioned)
# --------------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier            = "${var.project_name}-${var.environment}"
  engine                        = "aurora-postgresql"
  engine_mode                   = "provisioned"
  engine_version                = var.db_config.engine_version
  database_name                 = var.db_config.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [var.db_security_group_id]
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  deletion_protection                 = var.db_config.deletion_protection
  skip_final_snapshot                 = var.db_config.skip_final_snapshot
  final_snapshot_identifier           = "${var.project_name}-${var.environment}-final"
  backup_retention_period             = var.db_config.backup_retention_period

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

# --------------------------------------------------------------------------------
# Aurora Instances
# --------------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  for_each = var.db_config.instances

  identifier              = "${var.project_name}-${var.environment}-${each.key}"
  cluster_identifier      = aws_rds_cluster.this.id
  instance_class          = var.db_config.instance_class
  engine                  = aws_rds_cluster.this.engine
  engine_version          = aws_rds_cluster.this.engine_version
  db_parameter_group_name = aws_db_parameter_group.this.name

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Cluster Parameter Group
# --------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-cluster"
  family = "aurora-postgresql16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# --------------------------------------------------------------------------------
# DB Parameter Group
# --------------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-instance"
  family = "aurora-postgresql16"

  tags = {
    Name = "${var.project_name}-${var.environment}-instance"
  }
}

# --------------------------------------------------------------------------------
# Subnet Group
# --------------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}"
  subnet_ids = values(var.private_subnet_ids)

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
