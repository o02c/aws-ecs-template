# --------------------------------------------------------------------------------
# Firehose delivery streams — route ECS container logs to the shared log bucket.
# --------------------------------------------------------------------------------
# 3 streams into the same access-log bucket at different prefixes:
#   - audit:          structured events tagged `type=audit` (separate IAM scope later)
#   - ecs-logs-app:   app container stdout/stderr (non-audit)
#   - ecs-logs-nginx: nginx sidecar stdout/stderr
# Splitting by container yields per-container partition pruning in Athena and
# lets each table carry only its container's columns (cleaner schema).
# No CloudWatch Logs involved for container output; only FireLens → Firehose → S3.

locals {
  firehose_streams = {
    audit          = { s3_prefix = "audit" }
    ecs-logs-app   = { s3_prefix = "ecs-logs-app" }
    ecs-logs-nginx = { s3_prefix = "ecs-logs-nginx" }
  }
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  for_each = local.firehose_streams

  name        = "${var.project_name}-${var.environment}-${each.key}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = "arn:aws:s3:::${var.log_bucket_id}"

    prefix              = "${each.value.s3_prefix}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "${each.value.s3_prefix}-errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = var.firehose_buffering_interval_seconds
    compression_format = "GZIP"
    kms_key_arn        = var.s3_kms_key_arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}
