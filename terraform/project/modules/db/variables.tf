variable "project_name" {
  description = "Project name used for resource naming"
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  type        = map(string)
}

variable "db_security_group_id" {
  description = "Security group ID for the database"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for Aurora storage encryption"
  type        = string
}

variable "db_config" {
  description = <<-EOT
    Aurora cluster / instance settings. Environment-specific values
    (instance class, instance count, backup retention, etc.) live in
    environments/<env>/locals.tf so the env file is the UI of the database.
  EOT
  type = object({
    engine_version          = string
    database_name           = string
    iam_username            = string
    instance_class          = string
    instances               = map(object({}))
    backup_retention_period = number
    deletion_protection     = bool
    skip_final_snapshot     = bool
    # Enhanced Monitoring granularity in seconds (0 disables; valid: 1/5/10/15/30/60).
    monitoring_interval = number
  })
}
