# --------------------------------------------------------------------------------
# Cache Policy for API
# --------------------------------------------------------------------------------

resource "aws_cloudfront_cache_policy" "api" {
  name        = "${var.project_name}-${var.environment}-${var.lane}-api"
  comment     = "Cache policy for ${var.lane} API"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization", "Host"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }
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
