# --------------------------------------------------------------------------------
# SNS topic for S3 object-deletion notifications
# --------------------------------------------------------------------------------
# 不正/意図しないオブジェクト削除の検知用。s3:ObjectRemoved:* のみを購読するため、
# lifecycle 起因の削除 (s3:LifecycleExpiration:*) は別イベント種別で自然に除外される。
# KMS 暗号化トピック。発行元の S3 サービスは S3 CMK の key policy で
# kms:GenerateDataKey*/Decrypt を許可済み (kms モジュール s3_event_notifications)。

resource "aws_sns_topic" "s3_events" {
  name              = "${var.project_name}-${var.environment}-s3-events"
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-events"
  }
}

# Resource-based policy: S3 publishes object-removed events on our behalf.
# Scoped to the watched bucket ARNs (SourceArn) and our account (SourceAccount).
resource "aws_sns_topic_policy" "s3_events" {
  arn = aws_sns_topic.s3_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3EventNotificationPublish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.s3_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = [for b in var.buckets : b.arn]
          }
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

# After apply, AWS sends a confirmation email to each recipient. The subscription
# stays in "PendingConfirmation" until the link is clicked; events published
# before confirmation are silently dropped (verify-deploy.sh checks for this).
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_recipients)

  topic_arn = aws_sns_topic.s3_events.arn
  protocol  = "email"
  endpoint  = each.value
}
