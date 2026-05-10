variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "lanes" {
  description = "Per-lane data feeding the single CloudFront distribution. The lane with empty path_prefix serves the default behavior; others get an ordered behavior matching <path_prefix>*."
  type = map(object({
    path_prefix                    = string
    alb_arn                        = string
    alb_dns_name                   = string
    alb_security_group_id          = string
    s3_bucket_regional_domain_name = string
    s3_bucket_id                   = string
    cloudfront_oac_id              = string
  }))

  validation {
    condition     = length([for _, v in var.lanes : v if v.path_prefix == ""]) == 1
    error_message = "Exactly one lane must have an empty path_prefix (it serves the default cache behavior)."
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (must be in us-east-1)"
  type        = string
}

variable "hostname" {
  description = "Public FQDN for the distribution (CloudFront alias, Route53 A-alias, ALB origin Host header)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "enable_signing" {
  description = "Enable CloudFront signed URL support (applied to the default lane's S3 origin via signed_files_path_pattern)"
  type        = bool
}

variable "signing_public_key_pem" {
  description = "PEM-encoded public key for CloudFront signed URLs (empty when signing disabled)"
  type        = string
}

variable "files_path_pattern" {
  description = "Path pattern routed to the default lane's S3 origin behind a trusted key group (signed URLs)"
  type        = string
}

variable "waf_rate_limit" {
  description = "Maximum number of requests per 5-minute period per IP"
  type        = number
}

variable "ip_allowlist" {
  description = "Optional WAF IP allowlist. scope=\"admin\" gates only the non-default lane's path; scope=\"global\" gates all paths. Empty allowed_cidrs disables the rule entirely."
  type = object({
    scope         = string
    allowed_cidrs = list(string)
  })
  default = {
    scope         = "admin"
    allowed_cidrs = []
  }
  validation {
    condition     = contains(["admin", "global"], var.ip_allowlist.scope)
    error_message = "ip_allowlist.scope must be either \"admin\" or \"global\"."
  }
}

variable "geo_restriction_locations" {
  description = "List of ISO 3166-1 alpha-2 country codes for CloudFront geo restriction whitelist"
  type        = list(string)
}

variable "log_bucket_domain_name" {
  description = "Domain name of the S3 bucket for access logging"
  type        = string
}

variable "waf_log_bucket_arn" {
  description = "ARN of the dedicated aws-waf-logs-* bucket (direct WAF → S3 destination)"
  type        = string
}

variable "log_prefix" {
  description = "Prefix for CloudFront access log objects"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALBs reside (for VPC Origin SG lookup)"
  type        = string
}

variable "cache_ttl" {
  description = "Static-assets cache TTL (default and max, in seconds)"
  type = object({
    default_seconds = number
    max_seconds     = number
  })
}
