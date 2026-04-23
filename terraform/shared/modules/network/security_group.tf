# --------------------------------------------------------------------------------
# VPC Endpoint Security Group + Ingress Rules
# --------------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "${var.project_name}-${var.environment}-vpce"
  description = "Security group for shared VPC endpoints"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce"
  }
}

resource "aws_security_group_rule" "vpce_from_project" {
  for_each = var.project_vpc_cidrs

  security_group_id = aws_security_group.vpce.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  description       = "HTTPS from ${each.key} VPC"
}

resource "aws_security_group_rule" "vpce_from_shared" {
  security_group_id = aws_security_group.vpce.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
  description       = "HTTPS from shared VPC"
}
