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
}

variable "idle_timeout_seconds" {
  description = "ALB idle timeout in seconds (connection keep-alive budget)"
  type        = number
}

variable "container_port" {
  description = "Container port for ECS tasks (target group port)"
  type        = number
}

variable "target_group" {
  description = "Target group tuning: deregistration grace period and health check thresholds"
  type = object({
    deregistration_delay_seconds = number
    health_check = object({
      path                = string
      healthy_threshold   = number
      unhealthy_threshold = number
      timeout_seconds     = number
      interval_seconds    = number
    })
  })
}

variable "log_bucket_id" {
  description = "S3 bucket ID for ALB access logging"
  type        = string
}

variable "log_prefix" {
  description = "Prefix for ALB access log objects"
  type        = string
}
