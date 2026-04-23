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

variable "keys" {
  description = <<-EOT
    Map of CMK identifier to settings. Pass from environments/<env>/locals.tf
    so the env file is the single source of truth for key inventory.
  EOT
  type = map(object({
    description = string
    service     = string
  }))
}
