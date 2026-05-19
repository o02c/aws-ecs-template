variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of AZ to private subnet ID (Lambda is deployed across all)"
  type        = map(string)
}

variable "db_sql_security_group_id" {
  description = "Security group ID attached to the db_sql Lambdas"
  type        = string
}

variable "db_security_group_id" {
  description = "Security group ID of the Aurora cluster (ingress added here)"
  type        = string
}

variable "db_host" {
  description = "Aurora cluster writer endpoint"
  type        = string
}

variable "db_port" {
  description = "Aurora port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Target database name"
  type        = string
}

variable "db_cluster_resource_id" {
  description = "Aurora cluster resource ID (for RDS IAM auth ARN)"
  type        = string
}

variable "master_username" {
  description = "Master role name (DDL Lambda connects as this)"
  type        = string
  sensitive   = true
}

variable "master_user_secret_arn" {
  description = "ARN of the AWS-managed master user secret (DDL Lambda reads password from here)"
  type        = string
}

variable "dml_username" {
  description = <<-EOT
    PostgreSQL role used by the DML Lambda (IAM authentication).
    The role must exist in the database and have `rds_iam` granted — bootstrap
    once via the DDL Lambda before the DML Lambda can connect.
  EOT
  type        = string
  default     = "app_rw"
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN protecting the master user secret AND the SQL bucket"
  type        = string
}

variable "rds_kms_key_arn" {
  description = "KMS key ARN for Aurora storage (DDL Lambda needs Decrypt to read master secret which is wrapped with this key)"
  type        = string
}

variable "log_bucket_id" {
  description = "Shared access-log bucket ID (S3 server access log destination)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the Lambda log groups"
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for CloudWatch Logs encryption"
  type        = string
}

variable "shared_private_subnet_cidrs" {
  description = "Shared VPC private subnet CIDRs (Lambda reaches Secrets Manager / RDS API via TGW → shared VPC interface endpoints)"
  type        = list(string)
}

variable "s3_prefix_list_id" {
  description = "Prefix list ID for the S3 gateway endpoint in this VPC (Lambda fetches SQL files via it)"
  type        = string
}
