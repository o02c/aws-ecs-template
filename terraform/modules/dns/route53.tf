# --------------------------------------------------------------------------------
# Route53 Hosted Zone
# --------------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.domain_name}"
  }
}
