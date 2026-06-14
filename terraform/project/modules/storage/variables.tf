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

variable "object_lock" {
  description = <<-EOT
    S3 Object Lock (WORM) config for the assets bucket.
    enabled = true は新規バケット作成時のみ設定可能 (不可逆)。既存バケットを on に
    切替する場合はバケット recreate (= 資材退避 → 再配置) が必要。
    default_retention をセットするとバケット内全 object version に retention を適用。
  EOT
  type = object({
    enabled = bool
    default_retention = optional(object({
      mode = string
      days = number
    }))
  })
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent object versions are expired (掃除は WORM 保持日数より長く取る)"
  type        = number
}
