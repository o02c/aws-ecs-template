variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "private_subnets" {
  description = "Map of AZ to CIDR for private subnets"
  type        = map(string)
}

variable "security_groups" {
  description = "Set of security group identifiers to create"
  type        = set(string)
}

variable "gateway_endpoints" {
  description = "Map of identifier to service name for Gateway VPC endpoints"
  type        = map(string)
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID for shared VPC connectivity"
  type        = string
}

variable "shared_endpoint_phz_zone_ids" {
  description = "Map of endpoint name to Route53 PHZ zone ID from shared VPC"
  type        = map(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for CloudWatch Logs encryption"
  type        = string
}

variable "vpc_flow_log_retention" {
  description = <<-EOT
    VPC Flow Logs の出力先・保持設定。
    destinations.s3 = true → S3 直接配信 (parquet + Hive partitions)
    destinations.cloudwatch = true → CloudWatch Logs (log_class で IA も可)
    両方 true で二重出力。少なくとも一方を true にする必要あり (セキュリティガイド
    §2.2.19「VPCフローログを無効にすることの禁止」)。
  EOT
  type = object({
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
  })

  validation {
    condition     = var.vpc_flow_log_retention.destinations.cloudwatch || var.vpc_flow_log_retention.destinations.s3
    error_message = "VPC Flow Logs は最低 1 つの destination (cloudwatch / s3) を有効化する必要があります (セキュリティガイド §2.2.19)。"
  }
}

variable "access_logs_bucket_arn" {
  description = "Shared access-log S3 bucket ARN (used as VPC Flow Logs destination when destinations.s3 = true)"
  type        = string
}
