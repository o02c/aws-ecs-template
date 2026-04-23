# --------------------------------------------------------------------------------
# Fluent Bit diagnostic log group
# --------------------------------------------------------------------------------
# Application stdout/stderr is routed via FireLens → Firehose → S3 (no CW).
# This small log group captures the FireLens router's own startup and errors
# so the logging pipeline itself is observable. Short retention because
# volume is trivial compared to app logs.

resource "aws_cloudwatch_log_group" "fluent_bit" {
  name              = "/ecs/${var.project_name}-${var.environment}/fluent-bit"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  }
}
