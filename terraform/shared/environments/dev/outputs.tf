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

output "nat_gateway_public_ips" {
  description = "NAT Gateway public IPs"
  value       = module.network.nat_gateway_public_ips
}
