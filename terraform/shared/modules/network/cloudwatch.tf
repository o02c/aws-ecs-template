# --------------------------------------------------------------------------------
# CloudWatch Log Group for VPC Flow Logs
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${var.project_name}-${var.environment}"
  retention_in_days = var.flow_log_retention_days
  log_group_class   = var.flow_log_log_class
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log"
  }
}
