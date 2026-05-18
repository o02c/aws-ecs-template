# --------------------------------------------------------------------------------
# Fluent Bit diagnostic log group
# --------------------------------------------------------------------------------
# Application stdout/stderr is routed via FireLens → Firehose → S3 (no CW).
# This small log group captures the FireLens router's own startup and errors
# so the logging pipeline itself is observable. Volume is trivial compared
# to app logs; retention/class is tunable per env via var.fluent_bit_log_retention.

resource "aws_cloudwatch_log_group" "fluent_bit" {
  count = var.fluent_bit_log_retention.destinations.cloudwatch ? 1 : 0

  name              = "/ecs/${var.project_name}-${var.environment}/fluent-bit"
  retention_in_days = var.fluent_bit_log_retention.cloudwatch.retention_days
  log_group_class   = var.fluent_bit_log_retention.cloudwatch.log_class

  tags = {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  }
}
