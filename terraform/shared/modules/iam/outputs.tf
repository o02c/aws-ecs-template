output "user_arns" {
  description = "Map of IAM user name to ARN"
  value       = { for name, user in aws_iam_user.this : name => user.arn }
}

output "group_arns" {
  description = "Map of IAM group name to ARN"
  value       = { for name, group in aws_iam_group.this : name => group.arn }
}
