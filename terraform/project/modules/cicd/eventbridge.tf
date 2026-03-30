# --------------------------------------------------------------------------------
# S3 EventBridge Notification
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "artifact" {
  bucket      = aws_s3_bucket.artifact.id
  eventbridge = true
}

# --------------------------------------------------------------------------------
# EventBridge Rule (S3 → CodePipeline)
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "s3_trigger" {
  for_each = var.services

  name        = "${var.project_name}-${var.environment}-${each.key}-s3-trigger"
  description = "Trigger pipeline on S3 artifact upload for ${each.key}"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.artifact.id]
      }
      object = {
        key = [{
          prefix = "${each.key}/"
        }]
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-s3-trigger"
  }
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  for_each = var.services

  rule     = aws_cloudwatch_event_rule.s3_trigger[each.key].name
  arn      = aws_codepipeline.this[each.key].arn
  role_arn = aws_iam_role.eventbridge.arn
}
