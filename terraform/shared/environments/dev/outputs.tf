# --------------------------------------------------------------------------------
# Shared Infrastructure Outputs (consumed by project states)
# --------------------------------------------------------------------------------

output "transit_gateway_id" {
  description = "Transit Gateway ID for project VPC attachments"
  value       = module.network.transit_gateway_id
}

output "shared_vpc_id" {
  description = "Shared VPC ID"
  value       = module.network.vpc_id
}

output "shared_vpc_cidr" {
  description = "Shared VPC CIDR block"
  value       = module.network.vpc_cidr
}

output "endpoint_phz_zone_ids" {
  description = "Map of endpoint identifier to Route53 PHZ zone ID"
  value       = module.network.endpoint_phz_zone_ids
}
