output "topic_arns" {
  description = "Map of severity (critical / warning) to SNS topic ARN"
  value       = { for sev, t in aws_sns_topic.alert : sev => t.arn }
}

output "topic_names" {
  description = "Map of severity (critical / warning) to SNS topic name"
  value       = { for sev, t in aws_sns_topic.alert : sev => t.name }
}

output "alarm_arns" {
  description = "Map of alarm name to ARN (for scheduled enable/disable of alarm actions)"
  value = merge(
    { for k, a in aws_cloudwatch_metric_alarm.alb_5xx : a.alarm_name => a.arn },
    { (aws_cloudwatch_metric_alarm.aurora_cpu.alarm_name) = aws_cloudwatch_metric_alarm.aurora_cpu.arn },
    { (aws_cloudwatch_metric_alarm.aurora_connections.alarm_name) = aws_cloudwatch_metric_alarm.aurora_connections.arn },
    { for k, a in aws_cloudwatch_metric_alarm.ecs_running_gap : a.alarm_name => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.alb_healthy_host : a.alarm_name => a.arn },
    { for k, a in aws_cloudwatch_metric_alarm.firehose_delivery_failure : a.alarm_name => a.arn },
  )
}
