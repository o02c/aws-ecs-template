# --------------------------------------------------------------------------------
# Elastic IP for NAT Gateway
# --------------------------------------------------------------------------------

locals {
  nat_subnets = var.enable_nat ? (
    var.enable_ha_nat ? var.public_subnets : { for k, v in var.public_subnets : k => v if k == keys(var.public_subnets)[0] }
  ) : {}
}

resource "aws_eip" "nat" {
  for_each = local.nat_subnets

  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-nat-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# NAT Gateway
# --------------------------------------------------------------------------------

resource "aws_nat_gateway" "this" {
  for_each = aws_eip.nat

  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.this]
}
