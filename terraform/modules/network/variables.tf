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

variable "interface_endpoints" {
  description = "Map of identifier to service name for Interface VPC endpoints"
  type        = map(string)
}

variable "gateway_endpoints" {
  description = "Map of identifier to service name for Gateway VPC endpoints"
  type        = map(string)
}
