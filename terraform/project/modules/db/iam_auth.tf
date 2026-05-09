# --------------------------------------------------------------------------------
# RDS IAM Authentication Policy
# --------------------------------------------------------------------------------

resource "aws_iam_policy" "rds_iam_auth" {
  name        = "${var.project_name}-${var.environment}-rds-iam-auth"
  description = "Allow IAM authentication to Aurora cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "rds-db:connect"
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${aws_rds_cluster.this.cluster_resource_id}/${var.db_config.iam_username}"
      }
    ]
  })
}
