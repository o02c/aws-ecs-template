# --------------------------------------------------------------------------------
# Transit Gateway
# --------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.project_name}-${var.environment}-tgw"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${var.project_name}-${var.environment}-tgw"
  }
}

# --------------------------------------------------------------------------------
# Transit Gateway VPC Attachment (shared VPC)
# --------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "shared" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for s in aws_subnet.private : s.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-tgw-attach"
  }
}

# --------------------------------------------------------------------------------
# Transit Gateway Routes (return routes to project VPCs)
# --------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_route" "default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.this.association_default_route_table_id
}
