# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# --------------------------------------------------------------------------------
# VPC Endpoint Policy
# --------------------------------------------------------------------------------

locals {
  vpc_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAll"
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
      },
      {
        Sid       = "DenyOtherAwsAccountPrincipals"
        Effect    = "Deny"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# VPC Endpoints (Gateway)
# --------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = each.value
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  policy            = local.vpc_endpoint_policy

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# VPC Endpoints (Interface)
# --------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = each.value.service
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  policy              = local.vpc_endpoint_policy

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}
