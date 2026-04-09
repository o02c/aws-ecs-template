variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this project's VPC"
  type        = string
}

variable "shared_state_bucket" {
  description = "S3 bucket name for shared infrastructure state"
  type        = string
}

variable "shared_state_key" {
  description = "S3 key for shared infrastructure state file"
  type        = string
}

variable "domain_name" {
  description = "Root domain name for the application"
  type        = string
}

variable "cloudfront_signing_public_key_pem" {
  description = "PEM-encoded public key for CloudFront signed URLs"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudfront_signing_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the CloudFront signing private key"
  type        = string
  default     = ""
}

variable "db_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  sensitive   = true
}

