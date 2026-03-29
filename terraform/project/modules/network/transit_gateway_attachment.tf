# --------------------------------------------------------------------------------
# Transit Gateway VPC Attachment
# --------------------------------------------------------------------------------

locals {
  tgw_attachment = var.transit_gateway_id != "" ? { "main" = var.transit_gateway_id } : {}
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.tgw_attachment

  transit_gateway_id = each.value
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for s in aws_subnet.private : s.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-tgw-attach"
  }
}

# --------------------------------------------------------------------------------
# Default Route to Transit Gateway (for internet egress via shared VPC)
# --------------------------------------------------------------------------------

resource "aws_route" "tgw_default" {
  for_each = local.tgw_attachment

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = each.value
}
