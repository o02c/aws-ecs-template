# --------------------------------------------------------------------------------
# CloudWatch Log Group for VPC Flow Logs
# --------------------------------------------------------------------------------
# destinations.cloudwatch = true の場合にのみ作成。S3 直送 (parquet + Hive) を
# 採用する場合は count = 0 で skip され、IAM role / policy も同様に skip される。

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.vpc_flow_log_retention.destinations.cloudwatch ? 1 : 0

  name              = "/aws/vpc/flow-log/${var.project_name}-${var.environment}"
  retention_in_days = var.vpc_flow_log_retention.cloudwatch.retention_days
  log_group_class   = var.vpc_flow_log_retention.cloudwatch.log_class
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log"
  }
}
