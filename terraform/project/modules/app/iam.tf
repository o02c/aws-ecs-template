# --------------------------------------------------------------------------------
# ECS Task Execution Role (shared)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-${var.environment}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-task-execution"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --------------------------------------------------------------------------------
# ECS Task Roles (per-service)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  for_each = var.services

  name = "${var.project_name}-${var.environment}-${each.key}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-task"
  }
}

# Attach RDS IAM auth policy to task roles
resource "aws_iam_role_policy_attachment" "task_rds_auth" {
  for_each = var.services

  role       = aws_iam_role.task[each.key].name
  policy_arn = var.rds_iam_auth_policy_arn
}

# Attach S3 access policy to task roles
resource "aws_iam_role_policy_attachment" "task_s3_access" {
  for_each = var.services

  role       = aws_iam_role.task[each.key].name
  policy_arn = var.s3_access_policy_arns[each.value.lane]
}

# --------------------------------------------------------------------------------
# FireLens Permissions (CloudWatch Logs + Firehose)
# --------------------------------------------------------------------------------

resource "aws_iam_role_policy" "task_firelens" {
  for_each = var.services

  name = "firelens-access"
  role = aws_iam_role.task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.this[each.key].arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = "firehose:PutRecordBatch"
        Resource = aws_kinesis_firehose_delivery_stream.audit_logs.arn
      }
    ]
  })
}
