output "topic_arns" {
  description = "Map of severity (critical / warning) to SNS topic ARN"
  value       = { for sev, t in aws_sns_topic.alert : sev => t.arn }
}

output "topic_names" {
  description = "Map of severity (critical / warning) to SNS topic name"
  value       = { for sev, t in aws_sns_topic.alert : sev => t.name }
}
