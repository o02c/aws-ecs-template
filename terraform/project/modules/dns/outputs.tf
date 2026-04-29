output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Route53 hosted zone name servers (hand these to the domain registrar)"
  value       = aws_route53_zone.this.name_servers
}
