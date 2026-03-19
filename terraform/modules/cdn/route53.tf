# --------------------------------------------------------------------------------
# Route53 Alias Record for CloudFront
# --------------------------------------------------------------------------------

resource "aws_route53_record" "cloudfront_alias" {
  zone_id = var.route53_zone_id
  name    = "${var.lane}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
