output "vpc_id" {
  description = "Shared VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Shared VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map of AZ to public subnet ID"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_route_table_id" {
  description = "Transit Gateway default route table ID"
  value       = aws_ec2_transit_gateway.this.association_default_route_table_id
}

