output "policy_arn" {
  description = "IAM policy ARN granting SES send permission — attach to ECS task roles"
  value       = aws_iam_policy.send_email.arn
}

output "domain_identity_arn" {
  description = "SES domain identity ARN"
  value       = aws_ses_domain_identity.this.arn
}

output "sender_address" {
  description = "Default sender address (echoed back so callers can output it)"
  value       = var.sender_address
}

output "verified_recipients" {
  description = "List of verified recipient addresses (pending Gmail confirm until manually clicked)"
  value       = var.verified_recipients
}
