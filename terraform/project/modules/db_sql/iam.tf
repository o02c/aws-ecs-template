# --------------------------------------------------------------------------------
# Trust policy (shared by both Lambda roles)
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --------------------------------------------------------------------------------
# DDL Lambda role
# --------------------------------------------------------------------------------
# Master credentials via Secrets Manager → password auth.
# S3 read scoped to ddl/* only.

resource "aws_iam_role" "ddl" {
  name               = "${var.project_name}-${var.environment}-db-sql-ddl"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sql-ddl"
  }
}

# VPC ENI + base CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "ddl_vpc" {
  role       = aws_iam_role.ddl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ddl" {
  name = "db-sql-ddl"
  role = aws_iam_role.ddl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadMasterSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.master_user_secret_arn
      },
      {
        # Master secret is wrapped with the RDS KMS key (manage_master_user_password).
        Sid      = "DecryptMasterSecretEnvelope"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.rds_kms_key_arn
      },
      {
        Sid      = "ReadDdlSqlFiles"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.sql.arn}/ddl/*"
      },
      {
        # SQL bucket objects are SSE-KMS with the secrets key.
        Sid      = "DecryptSqlObjectEnvelope"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.secrets_kms_key_arn
      },
    ]
  })
}

# --------------------------------------------------------------------------------
# DML Lambda role
# --------------------------------------------------------------------------------
# RDS IAM auth (no password) as var.dml_username.
# S3 read scoped to dml/* only.

resource "aws_iam_role" "dml" {
  name               = "${var.project_name}-${var.environment}-db-sql-dml"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sql-dml"
  }
}

resource "aws_iam_role_policy_attachment" "dml_vpc" {
  role       = aws_iam_role.dml.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "dml" {
  name = "db-sql-dml"
  role = aws_iam_role.dml.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RdsIamConnect"
        Effect   = "Allow"
        Action   = "rds-db:connect"
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${var.db_cluster_resource_id}/${var.dml_username}"
      },
      {
        Sid      = "ReadDmlSqlFiles"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.sql.arn}/dml/*"
      },
      {
        Sid      = "DecryptSqlObjectEnvelope"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.secrets_kms_key_arn
      },
    ]
  })
}
