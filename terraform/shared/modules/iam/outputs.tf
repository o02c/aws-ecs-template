output "user_arns" {
  description = "Map of IAM user name to ARN"
  value       = { for name, user in aws_iam_user.this : name => user.arn }
}

output "mfa_enforced_group_arn" {
  description = "MFA-enforced group ARN (all users are auto-enrolled)"
  value       = aws_iam_group.mfa_enforced.arn
}
