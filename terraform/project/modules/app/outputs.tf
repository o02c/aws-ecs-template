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

output "nginx_ecr_repository_url" {
  description = "nginx ECR repository URL"
  value       = aws_ecr_repository.nginx.repository_url
}

output "ecr_public_cache_base_uri" {
  description = "Base URI of the ECR pull-through cache for public.ecr.aws upstream. Append <namespace>/<repo>:<tag> to consume any image (e.g. aws-observability/aws-for-fluent-bit:init-latest)."
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_pull_through_cache_rule.ecr_public.ecr_repository_prefix}"
}

output "fluent_bit_config_s3_arn" {
  description = "S3 ARN of Fluent Bit extra config for init process"
  value       = "arn:aws:s3:::${var.log_bucket_id}/${aws_s3_object.fluent_bit_config.key}"
}

output "firehose_stream_names" {
  description = "Map of firehose stream kind (audit / ecs-logs) to stream name"
  value       = { for k, s in aws_kinesis_firehose_delivery_stream.this : k => s.name }
}

output "ssm_parameter_arns" {
  description = "Map of service to SSM parameter ARN for Django secret key"
  value       = { for name, param in aws_ssm_parameter.django_secret_key : name => param.arn }
}
