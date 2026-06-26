# --------------------------------------------------------------------------------
# State machine execution logs
# --------------------------------------------------------------------------------
# Standard Workflows record history in Step Functions itself, but we also ship
# execution logs to CloudWatch (consistent with the Lambda/RDS/VPC log groups in
# this project). The /aws/vendedlogs/ prefix lets CloudWatch attach the log
# delivery resource policy automatically (avoids the 10-policy-per-account limit).

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.project_name}-${var.environment}-maintenance-toggle"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "/aws/vendedlogs/states/${var.project_name}-${var.environment}-maintenance-toggle"
  }
}
