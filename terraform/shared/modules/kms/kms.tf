# --------------------------------------------------------------------------------
# KMS Customer Managed Keys (Shared)
# --------------------------------------------------------------------------------

locals {
  keys = {
    general = {
      description = "CMK for shared infrastructure encryption"
      service     = null
    }
    logs = {
      description = "CMK for CloudWatch Logs encryption"
      service     = "logs.${var.aws_region}.amazonaws.com"
    }
  }
}

resource "aws_kms_key" "this" {
  for_each = local.keys

  description             = each.value.description
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key[each.key].json

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-${each.key}"
  }
}

resource "aws_kms_alias" "this" {
  for_each = local.keys

  name          = "alias/${var.project_name}-${var.environment}-shared-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

# --------------------------------------------------------------------------------
# Key Policies
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "key" {
  for_each = local.keys

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
}
