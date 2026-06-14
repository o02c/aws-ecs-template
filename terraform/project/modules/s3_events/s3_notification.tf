# --------------------------------------------------------------------------------
# S3 bucket notifications → SNS (object deletions)
# --------------------------------------------------------------------------------
# 1 バケットにつき通知設定は 1 個のみ。このモジュールが全プロジェクトバケットの
# 通知を一元管理する (cicd の artifact バケットは EventBridge 通知を別途持つため対象外)。
# depends_on でトピックポリシー適用後に通知を作成 (S3 は作成時に publish 可否を検証)。

resource "aws_s3_bucket_notification" "this" {
  for_each = var.buckets

  bucket = each.value.id

  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectRemoved:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_events]
}
