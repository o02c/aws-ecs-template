variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used to scope VPC endpoint policies to this account)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for shared VPC"
  type        = string
}

variable "public_subnets" {
  description = "Map of AZ to CIDR for public subnets (NAT Gateway)"
  type        = map(string)
}

variable "private_subnets" {
  description = "Map of AZ to CIDR for private subnets"
  type        = map(string)
}

variable "project_vpc_cidrs" {
  description = "Map of project name to VPC CIDR for return routes via TGW"
  type        = map(string)
}

variable "gateway_endpoints" {
  description = "Map of identifier to service name for Gateway VPC endpoints"
  type        = map(string)
}

variable "interface_endpoints" {
  description = <<-EOT
    Map of identifier to Interface VPC endpoint config.
    `wildcard = true` creates a `*.<private_dns_name>` alias record (needed by ECR DKR).
  EOT
  type = map(object({
    service  = string
    wildcard = bool
  }))
}

variable "kms_key_arn" {
  description = "KMS key ARN for CloudWatch Logs encryption"
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention period (days) for VPC flow log CloudWatch group"
  type        = number
}

variable "flow_log_log_class" {
  description = "CloudWatch Logs class for the flow log group (STANDARD | INFREQUENT_ACCESS). IA でコスト削減 (metric filter/subscription/data protection が制限される点に注意)。"
  type        = string
  default     = "INFREQUENT_ACCESS"
}
