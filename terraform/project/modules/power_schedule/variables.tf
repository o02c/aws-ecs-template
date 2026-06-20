variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "schedule" {
  description = <<-EOT
    Power schedule config. start / stop are independently toggled so a target can
    be stop-only (start.enabled = false). cron uses EventBridge Scheduler syntax,
    evaluated in `timezone`.
  EOT
  type = object({
    timezone = string
    db = object({
      stop  = object({ enabled = bool, cron = string })
      start = object({ enabled = bool, cron = string })
    })
    ecs = object({
      stop  = object({ enabled = bool, cron = string })
      start = object({ enabled = bool, cron = string, desired_count = number })
    })
    alarms = object({
      stop  = object({ enabled = bool, cron = string })
      start = object({ enabled = bool, cron = string })
    })
  })
}

variable "db_cluster_identifier" {
  description = "Aurora cluster identifier to stop/start"
  type        = string
}

variable "db_cluster_arn" {
  description = "Aurora cluster ARN (IAM resource scope)"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name owning the services to scale"
  type        = string
}

variable "ecs_service_names" {
  description = "ECS service names to scale to 0 / desired_count"
  type        = set(string)
}

variable "alarm_arns" {
  description = "Map of alarm name to ARN whose actions are toggled on stop/start"
  type        = map(string)
}
