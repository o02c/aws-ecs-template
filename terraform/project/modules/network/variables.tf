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

variable "flow_log_retention_days" {
  description = "Retention period (days) for VPC flow log CloudWatch group"
  type        = number
}
