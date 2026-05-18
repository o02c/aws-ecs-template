# --------------------------------------------------------------------------------
# Lifecycle Configuration (driven by var.log_retention)
# --------------------------------------------------------------------------------
# log_retention map から bucket 単位に pivot し、prefix ごとに 1 rule を生成する。
# transition の最低保管期間制約 (Standard-IA 30d / Glacier 系 90d) は呼び出し側で
# 担保する想定 (定数として locals.tf に記述)。
#
# 注意:
#   - GLACIER_IR / GLACIER / DEEP_ARCHIVE オブジェクトは Athena 直クエリ不可。
#     Athena 検索要件がある log_kind は IA 期間を伸ばすか transition を遅らせる。
#   - Object Lock 有効時、retention 期間中は expiration が機能しない。

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.log_kinds_by_bucket

  bucket = local.bucket_ids[each.key]

  dynamic "rule" {
    for_each = each.value
    content {
      id     = rule.key
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      abort_incomplete_multipart_upload {
        days_after_initiation = 7
      }
    }
  }
}
