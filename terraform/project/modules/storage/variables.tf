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

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption"
  type        = string
  default     = ""
}

variable "log_bucket_id" {
  description = "S3 bucket ID for S3 access logging"
  type        = string
}

variable "log_prefix" {
  description = "Prefix for S3 access log objects"
  type        = string
}
