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
        Sid    = "BucketObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*",
        ]
      },
      {
        # The bucket is SSE-KMS encrypted; PutObject must wrap the data key
        # via kms:GenerateDataKey and GetObject must unwrap via kms:Decrypt.
        # Scoped to the single project S3 key, not wildcard.
        Sid    = "BucketObjectKmsEnvelope"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = var.kms_key_arn
      },
    ]
  })
}
