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

  # Export the PostgreSQL engine log to the pre-created (retention + KMS) group.
  enabled_cloudwatch_logs_exports = var.postgresql_log_retention.destinations.cloudwatch ? ["postgresql"] : []

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }

  # Ensure RDS publishes into our managed log group rather than auto-creating one.
  depends_on = [aws_cloudwatch_log_group.postgresql]
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

  # Enhanced Monitoring (OS-level metrics to CloudWatch Logs). role_arn must be
  # unset when the interval is 0, so gate it on the same toggle.
  monitoring_interval = var.db_config.monitoring_interval
  monitoring_role_arn = var.db_config.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

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

  # Engine-log output (shipped to CloudWatch via enabled_cloudwatch_logs_exports).
  # Without these, the postgresql log only carries errors/startup. All dynamic —
  # applied without a reboot. Tune verbosity per env if log volume/cost matters.
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    # Audit schema changes (CREATE/ALTER/DROP) without logging every query.
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    # Slow-query log: statements taking >= 1s (milliseconds; -1 disables, 0 logs all).
    name  = "log_min_duration_statement"
    value = "1000"
  }
  parameter {
    # Log sessions waiting longer than deadlock_timeout — lock contention signal.
    name  = "log_lock_waits"
    value = "1"
  }

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
