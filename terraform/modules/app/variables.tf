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

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "alb_security_group_ids" {
  description = "Map of lane to ALB security group ID"
  type        = map(string)
}

variable "db_security_group_id" {
  description = "Security group ID for the database"
  type        = string
}

variable "vpce_security_group_id" {
  description = "Security group ID for VPC endpoints"
  type        = string
}

variable "db_cluster_arn" {
  description = "Aurora cluster ARN"
  type        = string
}

variable "db_resource_id" {
  description = "Aurora cluster resource ID"
  type        = string
}

variable "services" {
  description = "Map of ECS services"
  type = map(object({
    lane = string
  }))
}

variable "s3_bucket_arns" {
  description = "Map of lane to S3 bucket ARN"
  type        = map(string)
}

variable "rds_iam_auth_policy_arn" {
  description = "ARN of the RDS IAM authentication policy"
  type        = string
  default     = ""
}

variable "s3_access_policy_arns" {
  description = "Map of lane to S3 access policy ARN"
  type        = map(string)
  default     = {}
}

variable "s3_prefix_list_id" {
  description = "Prefix list ID for S3 gateway endpoint"
  type        = string
}

variable "container_port" {
  description = "Container port for ECS tasks"
  type        = number
  default     = 80
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
