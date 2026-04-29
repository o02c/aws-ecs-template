# --------------------------------------------------------------------------------
# ACM Certificate (Regional - for ALB)
# --------------------------------------------------------------------------------

resource "aws_acm_certificate" "regional" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "${var.project_name}-${var.environment}-regional"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "regional_validation" {
  for_each = {
    for dvo in aws_acm_certificate.regional.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [for record in aws_route53_record.regional_validation : record.fqdn]
}

# --------------------------------------------------------------------------------
# ACM Certificate (us-east-1 - for CloudFront)
# --------------------------------------------------------------------------------

resource "aws_acm_certificate" "cloudfront" {
  region = "us-east-1"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records are shared with regional cert (same domain, same records)

resource "aws_acm_certificate_validation" "cloudfront" {
  region = "us-east-1"

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.regional_validation : record.fqdn]
}
