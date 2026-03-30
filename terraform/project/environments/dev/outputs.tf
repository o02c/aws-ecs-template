# --------------------------------------------------------------------------------
# ecspresso References
# --------------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.app.ecr_repository_urls
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.app.task_execution_role_arn
}

output "task_role_arns" {
  description = "Map of service name to task role ARN"
  value       = module.app.task_role_arns
}

output "log_group_names" {
  description = "Map of service name to CloudWatch log group name"
  value       = module.app.log_group_names
}

output "target_group_arns" {
  description = "Map of lane to target group ARN"
  value       = { for lane, lb in module.lb : lane => lb.target_group_arn }
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = module.network.security_group_ids["ecs"]
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value       = module.network.private_subnet_ids
}

output "s3_bucket_ids" {
  description = "Map of lane to S3 bucket ID"
  value       = { for lane, s in module.storage : lane => s.bucket_id }
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.app.ecs_cluster_name
}

output "nginx_ecr_repository_url" {
  description = "nginx ECR repository URL"
  value       = module.app.nginx_ecr_repository_url
}

output "fluent_bit_ecr_repository_url" {
  description = "Fluent Bit ECR repository URL"
  value       = module.app.fluent_bit_ecr_repository_url
}

output "audit_log_bucket_id" {
  description = "Audit log S3 bucket ID"
  value       = module.app.audit_log_bucket_id
}

output "firehose_delivery_stream_name" {
  description = "Firehose delivery stream name for audit logs"
  value       = module.app.firehose_delivery_stream_name
}
