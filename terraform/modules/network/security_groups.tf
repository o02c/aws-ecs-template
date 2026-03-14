# --------------------------------------------------------------------------------
# Security Groups
# --------------------------------------------------------------------------------

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = "${var.project_name}-${var.environment}-${each.value}"
  description = "Security group for ${each.value}"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value}"
  }
}
