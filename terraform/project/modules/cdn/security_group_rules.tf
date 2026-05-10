# --------------------------------------------------------------------------------
# ALB Ingress from CloudFront VPC Origin
# --------------------------------------------------------------------------------
# CloudFront VPC Origin provisions one managed SG per VPC; each lane's ALB SG
# needs ingress from it. depends_on covers all VPC origin instances so the
# managed SG exists before the data lookup.

data "aws_security_group" "vpc_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  depends_on = [aws_cloudfront_vpc_origin.alb]
}

resource "aws_security_group_rule" "alb_from_vpc_origin" {
  for_each = var.lanes

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = each.value.alb_security_group_id
  source_security_group_id = data.aws_security_group.vpc_origin.id
  description              = "HTTPS from CloudFront VPC Origin (${each.key} lane)"
}
