output "topic_arn" {
  description = "ARN of the S3 object-deletion notification SNS topic"
  value       = aws_sns_topic.s3_events.arn
}
