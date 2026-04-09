# --------------------------------------------------------------------------------
# VPC Flow Logs
# --------------------------------------------------------------------------------

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-flow-log"
  }
}

# --------------------------------------------------------------------------------
# CloudWatch Logs
# --------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${var.project_name}-${var.environment}-shared"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-flow-log"
  }
}

# --------------------------------------------------------------------------------
# IAM Role for VPC Flow Logs
# --------------------------------------------------------------------------------

data "aws_iam_policy_document" "flow_log_assume" {
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
  name               = "${var.project_name}-${var.environment}-shared-flow-log"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-flow-log"
  }
}

data "aws_iam_policy_document" "flow_log" {
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
      aws_cloudwatch_log_group.flow_log.arn,
      "${aws_cloudwatch_log_group.flow_log.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "flow-log"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log.json
}
