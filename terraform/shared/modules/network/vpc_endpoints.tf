# --------------------------------------------------------------------------------
# VPC Endpoints (Gateway)
# --------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = each.value
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-${each.key}"
  }
}
