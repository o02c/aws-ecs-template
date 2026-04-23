# --------------------------------------------------------------------------------
# Public Subnets (for NAT Gateway)
# --------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Private Subnets
# --------------------------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${each.key}"
  }
}
