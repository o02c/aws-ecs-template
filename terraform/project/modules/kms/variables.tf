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
      context condition. Use ONLY for CloudWatch Logs keys — the condition keys
      on aws:logs:arn and matches nothing else. Null to skip.
    - cloudfront_enabled: when true, grant CloudFront service principal
      kms:Decrypt for any object encrypted with this key. Used by the S3 key
      so CloudFront OAC can fetch KMS-encrypted origin objects.
    - s3_event_notifications: when true, grant the S3 service principal
      kms:GenerateDataKey*/kms:Decrypt so S3 can deliver bucket event
      notifications to an SSE-KMS SNS topic encrypted with this key.
    - cloudwatch_sns_publish: when true, grant the CloudWatch service principal
      kms:GenerateDataKey*/kms:Decrypt so CloudWatch Alarms can publish to an
      SSE-KMS SNS topic encrypted with this key. Account-scoped (alarm publishes
      carry no logs encryption context, so `service` cannot cover this).
  EOT
  type = map(object({
    description            = string
    service                = string
    cloudfront_enabled     = optional(bool, false)
    s3_event_notifications = optional(bool, false)
    cloudwatch_sns_publish = optional(bool, false)
  }))
}
