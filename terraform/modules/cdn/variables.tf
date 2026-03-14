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
