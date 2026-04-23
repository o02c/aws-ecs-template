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

variable "alb_dns_name" {
  description = "ALB DNS name for VPC origin"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN for VPC origin"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  type        = string
}

variable "s3_bucket_id" {
  description = "S3 bucket ID"
  type        = string
}

variable "cloudfront_oac_id" {
  description = "CloudFront Origin Access Control ID"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (must be in us-east-1)"
  type        = string
}

variable "hostname" {
  description = "Public FQDN for this lane (CloudFront alias, Route53 A-alias, origin Host header)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "enable_signing" {
  description = "Enable CloudFront signed URL support"
  type        = bool
}

variable "signing_public_key_pem" {
  description = "PEM-encoded public key for CloudFront signed URLs (empty when signing disabled)"
  type        = string
}

variable "files_path_pattern" {
  description = "Path pattern for signed file delivery"
  type        = string
}

variable "waf_rate_limit" {
  description = "Maximum number of requests per 5-minute period per IP"
  type        = number
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
  description = "VPC ID where ALB resides (for VPC Origin SG lookup)"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID to add CloudFront VPC Origin ingress rule"
  type        = string
}

variable "cache_ttl" {
  description = "Static-assets cache TTL (default and max, in seconds)"
  type = object({
    default_seconds = number
    max_seconds     = number
  })
}

