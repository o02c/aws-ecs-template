# --------------------------------------------------------------------------------
# Lane Ordering (path-routing)
# --------------------------------------------------------------------------------
# CloudFront evaluates ordered_cache_behavior in declaration order, first match wins.
# Sort lanes by path_prefix length descending so the more specific prefix (e.g. /admin)
# is emitted before the shorter (e.g. ""). Length-prefixed sort keys keep stable ordering
# inside the alphabetical sort() helper.

locals {
  lane_keys_by_specificity = [
    for entry in reverse(sort([
      for k, v in var.lanes : format("%03d:%s", length(v.path_prefix), k)
    ])) : split(":", entry)[1]
  ]

  default_lane = one([for k, v in var.lanes : k if v.path_prefix == ""])
}

# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# --------------------------------------------------------------------------------
# VPC Origins (Internal ALB, one per lane)
# --------------------------------------------------------------------------------

resource "aws_cloudfront_vpc_origin" "alb" {
  for_each = var.lanes

  vpc_origin_endpoint_config {
    name                   = "${var.project_name}-${var.environment}-${each.key}-alb"
    arn                    = each.value.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-alb"
  }
}

# --------------------------------------------------------------------------------
# Cache Policy for Static Assets
# --------------------------------------------------------------------------------

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${var.project_name}-${var.environment}-static"
  comment     = "Cache policy for static assets (all lanes)"
  default_ttl = var.cache_ttl.default_seconds
  max_ttl     = var.cache_ttl.max_seconds
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
# CloudFront Distribution (single, path-routed across lanes)
# --------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment}"
  price_class         = "PriceClass_200"
  web_acl_id          = aws_wafv2_web_acl.this.arn
  default_root_object = "index.html"

  # ALB origins (VPC origin) — one per lane.
  # domain_name is the Host header CloudFront sends to the origin; all lanes
  # share the apex hostname so Django ALLOWED_HOSTS only needs one entry.
  dynamic "origin" {
    for_each = var.lanes
    content {
      domain_name = var.hostname
      origin_id   = "alb-${origin.key}"

      vpc_origin_config {
        vpc_origin_id = aws_cloudfront_vpc_origin.alb[origin.key].id
      }
    }
  }

  # S3 origins — one per lane.
  dynamic "origin" {
    for_each = var.lanes
    content {
      domain_name              = origin.value.s3_bucket_regional_domain_name
      origin_id                = "s3-${origin.key}"
      origin_access_control_id = origin.value.cloudfront_oac_id
    }
  }

  # Default behavior — static assets from the default lane's S3.
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${local.default_lane}"
    cache_policy_id        = aws_cloudfront_cache_policy.static.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # API behaviors (ALB) — one per lane, most specific path_prefix first.
  dynamic "ordered_cache_behavior" {
    for_each = local.lane_keys_by_specificity
    content {
      path_pattern             = "${var.lanes[ordered_cache_behavior.value].path_prefix}/api/*"
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods           = ["GET", "HEAD"]
      target_origin_id         = "alb-${ordered_cache_behavior.value}"
      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
      viewer_protocol_policy   = "redirect-to-https"
      compress                 = true
    }
  }

  # Signed file delivery (default lane's S3).
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_signing ? { "default" = true } : {}

    content {
      path_pattern           = var.files_path_pattern
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "s3-${local.default_lane}"
      cache_policy_id        = data.aws_cloudfront_cache_policy.caching_disabled.id
      viewer_protocol_policy = "redirect-to-https"
      compress               = true
      trusted_key_groups     = [aws_cloudfront_key_group.signing["default"].id]
    }
  }

  # Per-lane S3 prefix behaviors — non-default lanes only. ${prefix}* matches
  # both the bare prefix (e.g. /admin) and any descendant (/admin/index.html).
  dynamic "ordered_cache_behavior" {
    for_each = [for k in local.lane_keys_by_specificity : k if var.lanes[k].path_prefix != ""]
    content {
      path_pattern           = "${var.lanes[ordered_cache_behavior.value].path_prefix}*"
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "s3-${ordered_cache_behavior.value}"
      cache_policy_id        = aws_cloudfront_cache_policy.static.id
      viewer_protocol_policy = "redirect-to-https"
      compress               = true

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.rewrite_index.arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = var.geo_restriction_locations
    }
  }

  aliases = [var.hostname]

  # Access logging is configured out-of-band via CloudWatch Logs standard logging v2.
  # See cloudwatch_log_delivery.tf — that path writes Hive-partitioned objects so Athena can
  # actually prune partitions, which the legacy `logging_config` flat layout could not.

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
