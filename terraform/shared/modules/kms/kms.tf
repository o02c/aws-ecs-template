# --------------------------------------------------------------------------------
# KMS Customer Managed Keys (Shared)
# --------------------------------------------------------------------------------

locals {
  keys = {
    general = {
      description = "CMK for shared infrastructure encryption"
      service     = null
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
}
