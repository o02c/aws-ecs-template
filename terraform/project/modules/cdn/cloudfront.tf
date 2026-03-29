# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# --------------------------------------------------------------------------------
# VPC Origin (Internal ALB)
# --------------------------------------------------------------------------------

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.project_name}-${var.environment}-${var.lane}-alb"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}-alb-origin"
  }
}

# --------------------------------------------------------------------------------
# Cache Policy for Static Assets
# --------------------------------------------------------------------------------

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${var.project_name}-${var.environment}-${var.lane}-static"
  comment     = "Cache policy for ${var.lane} static assets"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# --------------------------------------------------------------------------------
# CloudFront Distribution
# --------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name}-${var.environment}-${var.lane}"
  price_class     = "PriceClass_200"
  web_acl_id      = aws_wafv2_web_acl.this.arn

  # ALB origin (VPC origin)
  origin {
    domain_name = "${var.lane}.${var.domain_name}"
    origin_id   = "alb"

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # S3 origin
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = var.cloudfront_oac_id
  }

  # Default behavior (API → ALB)
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  # Signed file delivery (S3)
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_signing ? { "default" = true } : {}

    content {
      path_pattern           = var.files_path_pattern
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "s3"
      cache_policy_id        = data.aws_cloudfront_cache_policy.caching_disabled.id
      viewer_protocol_policy = "redirect-to-https"
      compress               = true
      trusted_key_groups     = [aws_cloudfront_key_group.signing["default"].id]
    }
  }

  # Static assets behavior (S3)
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3"
    cache_policy_id        = aws_cloudfront_cache_policy.static.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = var.geo_restriction_locations
    }
  }

  aliases = var.aliases

  logging_config {
    bucket          = var.log_bucket_domain_name
    prefix          = var.log_prefix
    include_cookies = false
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}
