# --------------------------------------------------------------------------------
# CodeBuild Service Role
# --------------------------------------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-${var.environment}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-codebuild"
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-${var.environment}-codebuild"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.artifact.arn}/*"
      },
      {
        # ecr:GetAuthorizationToken does not support resource-level permissions.
        # AWS docs explicitly require Resource="*". The action only returns a
        # temporary token scoped to the caller's account, so blast radius is
        # account-local. Accepted deviation from security_prohibitions.md 2.2.26-7.
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:*:${var.aws_account_id}:repository/${var.project_name}-${var.environment}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters"
        ]
        Resource = "arn:aws:ecs:*:${var.aws_account_id}:cluster/${var.project_name}-${var.environment}"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "arn:aws:ecs:*:${var.aws_account_id}:service/${var.project_name}-${var.environment}/*"
      },
      {
        # ecs:DescribeTaskDefinition and ecs:RegisterTaskDefinition do not support
        # resource-level permissions (AWS service limitation). Task definitions
        # are account-local metadata; tag-based conditions could further scope in
        # the future. Accepted deviation from security_prohibitions.md 2.2.26-7.
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = values(var.ecs_task_role_arns)
      }
    ]
  })
}
