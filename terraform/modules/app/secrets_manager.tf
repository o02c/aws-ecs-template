# --------------------------------------------------------------------------------
# Secrets Manager Access (for CloudFront signing key)
# --------------------------------------------------------------------------------

resource "aws_iam_policy" "secrets_read" {
  for_each = var.cloudfront_signing_key_secret_arn != "" ? { "default" = true } : {}

  name = "${var.project_name}-${var.environment}-secrets-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.cloudfront_signing_key_secret_arn
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-secrets-read"
  }
}

resource "aws_iam_role_policy_attachment" "task_secrets_read" {
  for_each = var.cloudfront_signing_key_secret_arn != "" ? var.services : {}

  role       = aws_iam_role.task[each.key].name
  policy_arn = aws_iam_policy.secrets_read["default"].arn
}
