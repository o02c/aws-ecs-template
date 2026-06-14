variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used in SNS topic policy / KMS source-account conditions)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS topic encryption (the S3 CMK; its key policy must allow s3.amazonaws.com to GenerateDataKey*/Decrypt)"
  type        = string
}

variable "notification_recipients" {
  description = "Email addresses subscribed to the S3 object-deletion topic (manual confirm required)"
  type        = list(string)
}

variable "buckets" {
  description = <<-EOT
    Project buckets to watch for object deletions. key = 識別子 (display/for_each),
    value = { id, arn }。このモジュールが各バケットの aws_s3_bucket_notification を
    一元所有する (S3 はバケットにつき通知設定 1 個のみ) ため、他モジュールで
    aws_s3_bucket_notification を作らないこと。
  EOT
  type = map(object({
    id  = string
    arn = string
  }))
}
