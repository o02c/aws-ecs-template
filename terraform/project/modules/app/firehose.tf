# --------------------------------------------------------------------------------
# Firehose delivery streams — route ECS container logs to the shared log bucket.
# --------------------------------------------------------------------------------
# 2 streams into the same access-log bucket but at different prefixes:
#   - audit:    structured events tagged `type=audit` (restricted IAM access later)
#   - ecs-logs: everything else (nginx stdout/stderr + app stdout non-audit)
# No CloudWatch Logs involved for container output; only FireLens → Firehose → S3.

locals {
  firehose_streams = {
    audit    = { s3_prefix = "audit" }
    ecs-logs = { s3_prefix = "ecs-logs" }
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
