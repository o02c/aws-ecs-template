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

variable "cloudfront_signing_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the CloudFront signing private key (empty = signing disabled)"
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

variable "aws_account_id" {
  description = "AWS account ID for globally unique bucket naming"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN for S3 encryption (Firehose destinations)"
  type        = string
}

variable "log_bucket_id" {
  description = "Shared access-log S3 bucket ID (owns audit/ + ecs-logs/ prefixes)"
  type        = string
}
