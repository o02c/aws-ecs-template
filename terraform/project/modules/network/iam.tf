# --------------------------------------------------------------------------------
# IAM Role for VPC Flow Logs (CloudWatch Logs destination only)
# --------------------------------------------------------------------------------
# S3 直送モードでは IAM role 不要 (AWS managed の delivery.logs サービスプリンシパル
# をバケットポリシーで許可)。CW Logs 出力時のみ role/policy を作成する。

data "aws_iam_policy_document" "flow_log_assume" {
  count = local.vpc_flow_to_cw ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "flow_log" {
  count = local.vpc_flow_to_cw ? 1 : 0

  name               = "${var.project_name}-${var.environment}-flow-log"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume[0].json

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log"
  }
}

data "aws_iam_policy_document" "flow_log" {
  count = local.vpc_flow_to_cw ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = [
      aws_cloudwatch_log_group.flow_log[0].arn,
      "${aws_cloudwatch_log_group.flow_log[0].arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  count = local.vpc_flow_to_cw ? 1 : 0

  name   = "flow-log"
  role   = aws_iam_role.flow_log[0].id
  policy = data.aws_iam_policy_document.flow_log[0].json
}
