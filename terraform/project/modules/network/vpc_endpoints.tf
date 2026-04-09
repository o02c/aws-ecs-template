# --------------------------------------------------------------------------------
# VPC Endpoints (Gateway)
# --------------------------------------------------------------------------------

# Gateway endpoints (S3) do not support aws:PrincipalAccount condition
# for ECR internal layer access. Use default full-access policy.
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = each.value
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Route53 PHZ Association (shared VPC endpoints)
# --------------------------------------------------------------------------------

resource "aws_route53_zone_association" "shared_endpoints" {
  for_each = var.shared_endpoint_phz_zone_ids

  zone_id = each.value
  vpc_id  = aws_vpc.this.id
}
