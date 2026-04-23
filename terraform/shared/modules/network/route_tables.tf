# --------------------------------------------------------------------------------
# Public Route Table
# --------------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
  }
}

resource "aws_route" "public_to_projects" {
  for_each = var.project_vpc_cidrs

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------------------------
# Private Route Table
# --------------------------------------------------------------------------------

resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${each.key}"
  }
}

# Return routes from shared VPC to project VPCs via TGW
resource "aws_route" "private_to_projects" {
  for_each = {
    for pair in setproduct(keys(aws_route_table.private), keys(var.project_vpc_cidrs)) :
    "${pair[0]}-${pair[1]}" => {
      route_table_id = aws_route_table.private[pair[0]].id
      cidr_block     = var.project_vpc_cidrs[pair[1]]
    }
  }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
