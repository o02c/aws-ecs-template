variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for key policies"
  type        = string
}

variable "aws_region" {
  description = "AWS region for service principal conditions"
  type        = string
}

variable "keys" {
  description = <<-EOT
    Map of CMK identifier to settings. Pass from environments/<env>/locals.tf
    so the env file is the single source of truth for key inventory.

    - service: optional AWS service principal (e.g. "logs.<region>.amazonaws.com")
      that gets full crypto actions with a CloudWatch-Logs-specific encryption
      context condition. Null to skip.
    - cloudfront_enabled: when true, grant CloudFront service principal
      kms:Decrypt for any object encrypted with this key. Used by the S3 key
      so CloudFront OAC can fetch KMS-encrypted origin objects.
  EOT
  type = map(object({
    description        = string
    service            = string
    cloudfront_enabled = optional(bool, false)
  }))
}
