# --------------------------------------------------------------------------------
# State machine execution role
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.project_name}-${var.environment}-maintenance-toggle"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json

  tags = {
    Name = "${var.project_name}-${var.environment}-maintenance-toggle"
  }
}

data "aws_iam_policy_document" "sfn" {
  statement {
    sid = "WriteMaintenanceFlag"
    actions = [
      "cloudfront-keyvaluestore:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:PutKey",
    ]
    resources = [var.kvs_arn]
  }

  # CloudWatch Logs delivery actions don't support resource-level scoping, so "*"
  # is required (per the Step Functions logging docs).
  statement {
    sid = "Logging"
    actions = [
      "logs:CreateLogDelivery",
      "logs:CreateLogStream",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutLogEvents",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  # The log group is CMK-encrypted, so the execution role must be able to derive
  # a data key for it (the logs CMK policy already trusts CloudWatch Logs).
  statement {
    sid       = "LogsEncryption"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.logs_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.project_name}-${var.environment}-maintenance-toggle"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

# --------------------------------------------------------------------------------
# Scheduler execution role
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Confused-deputy guard scoped to this account. An aws:SourceArn ArnLike on
    # the schedule group is NOT added: EventBridge Scheduler's create-time role
    # validation performs the assume without populating aws:SourceArn, so an
    # ArnLike condition rejects CreateSchedule with "must allow Scheduler to
    # assume the role". aws:SourceAccount alone is the AWS-recommended minimum.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project_name}-${var.environment}-maintenance-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json

  tags = {
    Name = "${var.project_name}-${var.environment}-maintenance-scheduler"
  }
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "StartToggleExecution"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.toggle.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${var.project_name}-${var.environment}-maintenance-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
