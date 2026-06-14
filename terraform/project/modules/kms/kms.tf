# --------------------------------------------------------------------------------
# KMS Customer Managed Keys (project)
# --------------------------------------------------------------------------------
# Keys are defined in environments/<env>/locals.tf and passed via var.keys.
# shared 側の同名 key とは state 境界が違うため別物（terraform-conventions §8）。

resource "aws_kms_key" "this" {
  for_each = var.keys

  description             = each.value.description
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key[each.key].json

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = "alias/${var.project_name}-${var.environment}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

# --------------------------------------------------------------------------------
# Key Policies
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "key" {
  for_each = var.keys

  # Allow account root full access
  statement {
    sid    = "AllowRootAccount"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow service principal access (only for keys that need it)
  dynamic "statement" {
    for_each = each.value.service != null ? { service = each.value.service } : {}

    content {
      sid    = "AllowServicePrincipal"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = [statement.value]
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:*"]
      }
    }
  }

  # CloudFront OAC needs kms:Decrypt to fetch KMS-encrypted origin objects.
  # Scoped to aws:SourceAccount rather than the distribution ARN so we avoid
  # the circular dep (KMS key → S3 bucket → CloudFront distribution → KMS key).
  # Only our own CloudFront distributions run in this account, so the account
  # condition is tight enough.
  dynamic "statement" {
    for_each = each.value.cloudfront_enabled ? { enabled = true } : {}

    content {
      sid    = "AllowCloudFrontServicePrincipal"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      actions   = ["kms:Decrypt"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.aws_account_id]
      }
    }
  }

  # S3 delivers bucket event notifications (s3:ObjectRemoved:*) to an SSE-KMS
  # SNS topic encrypted with this key. S3 calls kms:GenerateDataKey* / kms:Decrypt
  # on our behalf to encrypt the message. Scoped to our own account so only this
  # account's S3 service can use the key for SNS encryption.
  dynamic "statement" {
    for_each = each.value.s3_event_notifications ? { enabled = true } : {}

    content {
      sid    = "AllowS3EventNotificationPublish"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["s3.amazonaws.com"]
      }

      actions = [
        "kms:GenerateDataKey*",
        "kms:Decrypt",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.aws_account_id]
      }
    }
  }
}
