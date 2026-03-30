variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to associate the DNS Firewall rule group"
  type        = string
}

variable "block_domains" {
  description = "List of domains to block (e.g. *.malicious.example.com)"
  type        = list(string)
  default     = []
}
