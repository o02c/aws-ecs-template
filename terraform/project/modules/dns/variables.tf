variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g. o2c.click)"
  type        = string
}

variable "manage_registrar_ns" {
  description = "Update domain registrar nameservers to match the hosted zone (for AWS-registered domains)"
  type        = bool
  default     = false
}
