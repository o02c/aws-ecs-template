# --------------------------------------------------------------------------------
# S3 Access Policy for ECS Tasks
# --------------------------------------------------------------------------------

resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-${var.environment}-${var.lane}-s3-access"
  description = "Allow ECS tasks to access ${var.lane} S3 bucket including presigned URLs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }
    ]
  })
}
