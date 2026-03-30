output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "security_group_ids" {
  description = "Map of security group identifier to ID"
  value       = { for name, sg in aws_security_group.this : name => sg.id }
}

output "s3_prefix_list_id" {
  description = "Prefix list ID for S3 gateway endpoint"
  value       = aws_vpc_endpoint.gateway["s3"].prefix_list_id
}
