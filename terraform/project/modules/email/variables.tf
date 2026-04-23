variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Sender domain (must match a Route53 hosted zone)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DKIM / SPF / DMARC / MAIL FROM records"
  type        = string
}

variable "mail_from_subdomain" {
  description = "Subdomain label for the custom MAIL FROM (e.g. `bounce` → bounce.<domain>)"
  type        = string
}

variable "sender_address" {
  description = "Default sender address the ECS tasks will use (must be @<domain>)"
  type        = string
}

variable "verified_recipients" {
  description = "Sandbox-verified recipient email addresses (manual Gmail confirm required after apply)"
  type        = list(string)
}

variable "dmarc_rua_address" {
  description = "DMARC aggregate report recipient (usually postmaster@<domain>)"
  type        = string
}
