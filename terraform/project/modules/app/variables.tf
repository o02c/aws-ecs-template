variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  type        = map(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "alb_security_group_ids" {
  description = "Map of lane to ALB security group ID"
  type        = map(string)
}

variable "db_security_group_id" {
  description = "Security group ID for the database"
  type        = string
}

variable "shared_private_subnet_cidrs" {
  description = "Shared VPC private subnet CIDRs where VPC endpoints are deployed"
  type        = list(string)
}

variable "db_cluster_arn" {
  description = "Aurora cluster ARN"
  type        = string
}

variable "db_resource_id" {
  description = "Aurora cluster resource ID"
  type        = string
}

variable "services" {
  description = "Map of ECS services"
  type = map(object({
    lane = string
  }))
}

variable "s3_bucket_arns" {
  description = "Map of lane to S3 bucket ARN"
  type        = map(string)
}

variable "rds_iam_auth_policy_arn" {
  description = "ARN of the RDS IAM authentication policy"
  type        = string
}

variable "s3_access_policy_arns" {
  description = "Map of lane to S3 access policy ARN"
  type        = map(string)
}

variable "s3_prefix_list_id" {
  description = "Prefix list ID for S3 gateway endpoint"
  type        = string
}

variable "cloudfront_signing_enabled" {
  description = "Plan-time flag: whether to attach the secrets-read policy to task roles. Paired with cloudfront_signing_key_secret_arn which is apply-time unknown when signing keys are generated in-terraform."
  type        = bool
}

variable "cloudfront_signing_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the CloudFront signing private key (consumed only when cloudfront_signing_enabled = true)"
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN used to encrypt the CloudFront signing Secrets Manager secret (tasks need kms:Decrypt to read the secret value)"
  type        = string
}

variable "container_port" {
  description = "Container port for ECS tasks"
  type        = number
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for SSM parameter / logs encryption key (used by task execution role)"
  type        = string
}

variable "firehose_buffering_interval_seconds" {
  description = "Firehose buffering interval (seconds) for ECS log delivery streams"
  type        = number
}

variable "fluent_bit_log_retention" {
  description = <<-EOT
    FireLens (Fluent Bit) router 自身の診断ログ設定。
    destinations.cloudwatch = false にすると Log Group を作らない (ECS task の log driver
    も変更必要なので通常は true 固定)。
    log_class = "INFREQUENT_ACCESS" でコスト削減 (metric filter / subscription / data
    protection が制限される点に注意)。
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
    s3 = optional(any)
  })
}

variable "aws_account_id" {
  description = "AWS account ID for globally unique bucket naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used for ECR registry URI construction)"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN for S3 encryption (Firehose destinations)"
  type        = string
}

variable "ecr_kms_key_arn" {
  description = "KMS key ARN for ECR repository encryption (SSE-KMS)"
  type        = string
}

variable "log_bucket_id" {
  description = "Shared access-log S3 bucket ID (owns audit/ + ecs-logs/ prefixes)"
  type        = string
}

variable "email_enabled" {
  description = "Plan-time flag: whether to attach the SES policy to task roles. policy_arn may be apply-time known."
  type        = bool
}

variable "email_policy_arn" {
  description = "IAM policy ARN for SES send (consumed only when email_enabled = true)"
  type        = string
}
