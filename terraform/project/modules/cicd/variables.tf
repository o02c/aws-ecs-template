variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecr_repository_urls" {
  description = "Map of service to ECR repository URL"
  type        = map(string)
}

variable "services" {
  description = "Map of services"
  type = map(object({
    lane = string
  }))
}

variable "ecs_task_role_arns" {
  description = "Map of service to ECS task role ARN"
  type        = map(string)
}
