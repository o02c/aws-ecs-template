# --------------------------------------------------------------------------------
# CloudWatch Log Groups
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  for_each = var.services

  name              = "/ecs/${var.project_name}-${var.environment}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}
