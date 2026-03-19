variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "domain_name" {
  description = "Root domain name for the application"
  type        = string
}

variable "db_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "db_master_password" {
  description = "Master password for Aurora cluster"
  type        = string
  sensitive   = true
}
