variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
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

variable "master_password" {
  description = "Master password for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for Aurora storage encryption"
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Default database name"
  type        = string
  default     = "app"
}

variable "db_instances" {
  description = "Map of DB instance identifiers"
  type        = map(object({}))
  default = {
    writer = {}
    reader = {}
  }
}

variable "serverless_min_capacity" {
  description = "Minimum ACU for Serverless v2"
  type        = number
  default     = 0.5
}

variable "serverless_max_capacity" {
  description = "Maximum ACU for Serverless v2"
  type        = number
  default     = 4
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = false
}

variable "db_iam_username" {
  description = "Database username for IAM authentication"
  type        = string
  default     = "app"
}
