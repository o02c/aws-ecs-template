variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for key policies"
  type        = string
}

variable "aws_region" {
  description = "AWS region for service principal conditions"
  type        = string
}
