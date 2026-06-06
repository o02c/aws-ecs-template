# --------------------------------------------------------------------------------
# PostgreSQL engine log group
# --------------------------------------------------------------------------------
# Pre-create the log group RDS publishes to (name is fixed by RDS:
# /aws/rds/cluster/<cluster-id>/postgresql) so we own its retention, log class,
# and KMS encryption instead of letting RDS auto-create an unmanaged group.
# The cluster's enabled_cloudwatch_logs_exports depends on this (see aurora.tf).

resource "aws_cloudwatch_log_group" "postgresql" {
  count = var.postgresql_log_retention.destinations.cloudwatch ? 1 : 0

  name              = "/aws/rds/cluster/${var.project_name}-${var.environment}/postgresql"
  retention_in_days = var.postgresql_log_retention.cloudwatch.retention_days
  log_group_class   = var.postgresql_log_retention.cloudwatch.log_class
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-postgresql"
  }
}
