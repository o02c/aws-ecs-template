# --------------------------------------------------------------------------------
# VPC Flow Logs
# --------------------------------------------------------------------------------
# destinations を真実源として CW Logs / S3 / 両方 を選択可能。
# aws_flow_log は 1 リソースで 1 destination しか持てないため、両方有効な場合は
# 2 リソースを for_each で作成する。
# S3 直送モードでは parquet + Hive 互換パーティションで配信し、Athena partition
# projection クエリで効率的に検索可能 (per-hour partition で 1 時間単位)。
# IAM role は CW 配信時のみ必要で、S3 直送では AWS managed の delivery.logs
# サービスプリンシパルがバケットポリシーで許可されている前提。

locals {
  vpc_flow_to_cw = var.vpc_flow_log_retention.destinations.cloudwatch
  vpc_flow_to_s3 = var.vpc_flow_log_retention.destinations.s3

  vpc_flow_destinations = merge(
    local.vpc_flow_to_cw ? { cloudwatch = "cloudwatch" } : {},
    local.vpc_flow_to_s3 ? { s3 = "s3" } : {},
  )
}

resource "aws_flow_log" "this" {
  for_each = local.vpc_flow_destinations

  vpc_id       = aws_vpc.this.id
  traffic_type = "ALL"

  log_destination_type = each.key == "s3" ? "s3" : "cloud-watch-logs"
  log_destination = (
    each.key == "s3"
    ? "${var.access_logs_bucket_arn}/${var.vpc_flow_log_retention.s3.prefix}"
    : aws_cloudwatch_log_group.flow_log[0].arn
  )

  iam_role_arn = each.key == "s3" ? null : aws_iam_role.flow_log[0].arn

  dynamic "destination_options" {
    for_each = each.key == "s3" ? [1] : []
    content {
      file_format                = "parquet"
      hive_compatible_partitions = true
      per_hour_partition         = true
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}
