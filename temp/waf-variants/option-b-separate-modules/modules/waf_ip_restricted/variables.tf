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

variable "ip_allowlist" {
  description = "CIDR blocks allowed. Required (non-empty)."
  type        = list(string)
}
