# --------------------------------------------------------------------------------
# ALB Ingress from CloudFront VPC Origin
# --------------------------------------------------------------------------------

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
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.alb_security_group_id
  source_security_group_id = data.aws_security_group.vpc_origin.id
  description              = "HTTPS from CloudFront VPC Origin"
}
