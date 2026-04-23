# --------------------------------------------------------------------------------
# IAM policy for ECS task role to send email via SES.
# --------------------------------------------------------------------------------
# `ses:SendEmail` / `ses:SendRawEmail` both support resource-level permissions,
# so we scope Resource to our domain identity and recipient identities.
# This complies with terraform-conventions §7 / security_prohibitions 2.2.26-7
# (identity policy must not grant Allow + Resource="*" / Action="*").

resource "aws_iam_policy" "send_email" {
  name        = "${var.project_name}-${var.environment}-ses-send"
  description = "Send email from ${var.domain_name} via SES (sandbox, allowlisted recipients only)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendFromDomain"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
        ]
        # Resource scoped to the domain identity. SES evaluates both domain
        # and email identities for the Source address check.
        Resource = concat(
          [aws_ses_domain_identity.this.arn],
          [for id in aws_ses_email_identity.recipient : id.arn],
        )
        # Defense in depth: even if Resource were wider, this condition
        # restricts the Source field to exactly our sender_address.
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.sender_address
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ses-send"
  }
}
