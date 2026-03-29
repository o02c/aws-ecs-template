variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
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

variable "enable_ha_nat" {
  description = "Enable HA NAT Gateway (one per AZ). Set to false for single NAT (cost saving)"
  type        = bool
  default     = false
}

variable "project_vpc_cidrs" {
  description = "Map of project name to VPC CIDR for return routes via TGW"
  type        = map(string)
  default     = {}
}

variable "gateway_endpoints" {
  description = "Map of identifier to service name for Gateway VPC endpoints"
  type        = map(string)
  default     = {}
}
