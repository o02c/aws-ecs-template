variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region (used for ELB account ID mapping)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for globally unique bucket naming"
  type        = string
}

variable "log_retention" {
  description = <<-EOT
    Per-log-kind retention/destination config. Map key is the log kind
    (audit / ecs_logs / vpc_flow / alb_access / cloudfront_access / s3_access / waf / fluent_bit).
    destinations.s3 = true で S3 prefix lifecycle が生成され、destinations.cloudwatch
    は各モジュール側で CW Log Group の有無を決める。
  EOT
  type = map(object({
    destinations = object({
      cloudwatch = bool
      s3         = bool
    })
    cloudwatch = optional(object({
      retention_days = number
      log_class      = string
    }))
    s3 = optional(object({
      bucket = string
      prefix = string
      transitions = list(object({
        days          = number
        storage_class = string
      }))
      expiration_days = optional(number)
    }))
  }))
}

variable "log_buckets" {
  description = <<-EOT
    Per-bucket Object Lock config. key = "access_logs" | "waf_logs".
    object_lock.enabled は新規バケット作成時のみ有効化可能 (不可逆)。
    default_retention をセットするとバケット内全 object に WORM 適用。
  EOT
  type = map(object({
    object_lock = object({
      enabled = bool
      default_retention = optional(object({
        mode = string
        days = number
      }))
    })
  }))
}

variable "athena_results_expiration_days" {
  description = "Days after which Athena query result objects are expired (results are reproducible from source logs)"
  type        = number
  default     = 30
}
