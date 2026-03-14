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
