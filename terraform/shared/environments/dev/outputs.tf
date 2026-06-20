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

output "shared_private_subnet_cidrs" {
  description = "Shared VPC private subnet CIDRs (where VPC endpoints are deployed)"
  value       = module.network.private_subnet_cidrs
}

output "endpoint_phz_zone_ids" {
  description = "Map of endpoint identifier to Route53 PHZ zone ID"
  value       = module.network.endpoint_phz_zone_ids
}

output "cloudfront_web_acl_arn" {
  description = "Account-wide CLOUDFRONT Web ACL ARN (empty when local.waf.enabled is false). Projects pass this to module.cdn web_acl_arn where they defer association to the shared/FMS ACL."
  value       = length(module.waf) > 0 ? one([for _, m in module.waf : m.web_acl_arn]) : ""
}
