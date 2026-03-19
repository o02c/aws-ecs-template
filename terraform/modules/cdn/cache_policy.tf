# --------------------------------------------------------------------------------
# Cache Policy for API (Managed CachingDisabled)
# --------------------------------------------------------------------------------

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
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
