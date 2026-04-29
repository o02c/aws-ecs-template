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

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation records"
  type        = string
}
