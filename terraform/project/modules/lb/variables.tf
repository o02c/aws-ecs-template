variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "lane" {
  description = "Traffic lane identifier"
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

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/health"
}

variable "container_port" {
  description = "Container port for ECS tasks"
  type        = number
  default     = 80
}

variable "log_bucket_id" {
  description = "S3 bucket ID for ALB access logging"
  type        = string
}

variable "log_prefix" {
  description = "Prefix for ALB access log objects"
  type        = string
}
