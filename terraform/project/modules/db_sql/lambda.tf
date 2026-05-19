# --------------------------------------------------------------------------------
# Lambda package
# --------------------------------------------------------------------------------
# Layout (one dir per logical function so a module with multiple distinct
# handlers can scale by adding sibling dirs under files/):
#   files/<fn>/src/        ← zipped to Lambda
#   files/<fn>/requirements.txt
#   files/<fn>/vendor.sh   ← re-vendor deps into src/ when requirements change
#
# Both Lambdas in this module share the same handler code, so only one
# function dir ("runner") exists and the archive is reused.

data "archive_file" "runner" {
  type        = "zip"
  source_dir  = "${path.module}/files/runner/src"
  output_path = "${path.module}/files/runner/lambda.zip"
}

# --------------------------------------------------------------------------------
# DDL Lambda: master user via Secrets Manager, S3 prefix ddl/
# --------------------------------------------------------------------------------

resource "aws_lambda_function" "ddl" {
  function_name = "${var.project_name}-${var.environment}-db-sql-ddl"
  role          = aws_iam_role.ddl.arn
  filename      = data.archive_file.runner.output_path
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  source_code_hash = data.archive_file.runner.output_base64sha256

  vpc_config {
    subnet_ids         = values(var.private_subnet_ids)
    security_group_ids = [var.db_sql_security_group_id]
  }

  environment {
    variables = {
      DB_HOST    = var.db_host
      DB_PORT    = tostring(var.db_port)
      DB_NAME    = var.db_name
      DB_USER    = var.master_username
      AUTH_MODE  = "secret"
      SECRET_ARN = var.master_user_secret_arn
      SQL_BUCKET = aws_s3_bucket.sql.id
      SQL_PREFIX = "ddl/"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sql-ddl"
  }
}

resource "aws_cloudwatch_log_group" "ddl" {
  name              = "/aws/lambda/${aws_lambda_function.ddl.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "/aws/lambda/${aws_lambda_function.ddl.function_name}"
  }
}

# --------------------------------------------------------------------------------
# DML Lambda: RDS IAM auth as var.dml_username, S3 prefix dml/
# --------------------------------------------------------------------------------

resource "aws_lambda_function" "dml" {
  function_name = "${var.project_name}-${var.environment}-db-sql-dml"
  role          = aws_iam_role.dml.arn
  filename      = data.archive_file.runner.output_path
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  source_code_hash = data.archive_file.runner.output_base64sha256

  vpc_config {
    subnet_ids         = values(var.private_subnet_ids)
    security_group_ids = [var.db_sql_security_group_id]
  }

  environment {
    variables = {
      DB_HOST    = var.db_host
      DB_PORT    = tostring(var.db_port)
      DB_NAME    = var.db_name
      DB_USER    = var.dml_username
      AUTH_MODE  = "iam"
      SQL_BUCKET = aws_s3_bucket.sql.id
      SQL_PREFIX = "dml/"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sql-dml"
  }
}

resource "aws_cloudwatch_log_group" "dml" {
  name              = "/aws/lambda/${aws_lambda_function.dml.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "/aws/lambda/${aws_lambda_function.dml.function_name}"
  }
}
