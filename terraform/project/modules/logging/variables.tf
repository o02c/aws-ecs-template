variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region (used for ELB account ID mapping)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for globally unique bucket naming"
  type        = string
}

variable "access_log_lifecycle" {
  description = "Access-log bucket lifecycle: days until GLACIER transition and expiration"
  type = object({
    transition_days = number
    expiration_days = number
  })
}
