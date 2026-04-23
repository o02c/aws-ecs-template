# --------------------------------------------------------------------------------
# SNS topics + topic policy + email subscriptions
# --------------------------------------------------------------------------------
# Two severity-tiered topics so future subscribers (PagerDuty, Slack) can
# route differently. Both receive the same email address set in dev.
# KMS-encrypted at rest; topic policy allows cloudwatch.amazonaws.com to
# publish (resource-based policy — terraform-conventions §7 identity-policy
# rules do not apply).

locals {
  severities = toset(["critical", "warning"])

  # Flatten (severity × recipient) for per-subscription for_each
  subscriptions = merge([
    for sev in local.severities : {
      for recipient in var.alarm_recipients :
      "${sev}:${recipient}" => {
        severity  = sev
        recipient = recipient
      }
    }
  ]...)
}

resource "aws_sns_topic" "alert" {
  for_each = local.severities

  name              = "${var.project_name}-${var.environment}-alert-${each.key}"
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-alert-${each.key}"
  }
}

# Resource-based policy: CloudWatch Alarm service publishes on our behalf.
# Scoped by aws:SourceAccount so only our account can trigger publish.
resource "aws_sns_topic_policy" "alert" {
  for_each = aws_sns_topic.alert

  arn = each.value.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = each.value.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.subscriptions

  topic_arn = aws_sns_topic.alert[each.value.severity].arn
  protocol  = "email"
  endpoint  = each.value.recipient

  # After apply, AWS sends a confirmation email to each recipient. The
  # subscription stays in "PendingConfirmation" state until the recipient
  # manually clicks the link. Alarms published before confirmation are
  # silently dropped, so verify via `aws sns list-subscriptions-by-topic`.
}
