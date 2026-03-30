output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "ecr_repository_urls" {
  description = "Map of service to ECR repository URL"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arns" {
  description = "Map of service to task role ARN"
  value       = { for name, role in aws_iam_role.task : name => role.arn }
}

output "log_group_names" {
  description = "Map of service to CloudWatch log group name"
  value       = { for name, lg in aws_cloudwatch_log_group.this : name => lg.name }
}

output "nginx_ecr_repository_url" {
  description = "nginx ECR repository URL"
  value       = aws_ecr_repository.nginx.repository_url
}

output "fluent_bit_init_image" {
  description = "Fluent Bit init-latest image URI (mirrored to private ECR)"
  value       = "${aws_ecr_repository.fluent_bit.repository_url}:init-latest"
}

output "fluent_bit_config_s3_arn" {
  description = "S3 ARN of Fluent Bit extra config for init process"
  value       = "arn:aws:s3:::${aws_s3_bucket.audit_logs.id}/${aws_s3_object.fluent_bit_config.key}"
}

output "audit_log_bucket_id" {
  description = "Audit log S3 bucket ID"
  value       = aws_s3_bucket.audit_logs.id
}

output "firehose_delivery_stream_name" {
  description = "Firehose delivery stream name for audit logs"
  value       = aws_kinesis_firehose_delivery_stream.audit_logs.name
}
