# --------------------------------------------------------------------------------
# CloudFront Function: trailing-slash + lane-prefix index handling
# --------------------------------------------------------------------------------
# Two rewrites on S3-origin behaviors so the entry URL behaves like a directory:
#   1. URI ending with `/`  → append `index.html` (e.g. /admin/ → /admin/index.html)
#   2. URI exactly equal to a non-default lane prefix → 301 to `<uri>/` (e.g.
#      /admin → /admin/), so the browser settles on the canonical form before
#      rule 1 fires on the redirect target.
# Free tier: 2M invocations/month.

locals {
  lane_redirect_prefixes = [for k, v in var.lanes : v.path_prefix if v.path_prefix != ""]
}

resource "aws_cloudfront_function" "rewrite_index" {
  name    = "${var.project_name}-${var.environment}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  comment = "Trailing-slash → index.html + lane-prefix → <prefix>/ redirect"
  publish = true
  code    = <<-EOT
    var LANE_PREFIXES = ${jsonencode(local.lane_redirect_prefixes)};

    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
        return request;
      }

      for (var i = 0; i < LANE_PREFIXES.length; i++) {
        if (uri === LANE_PREFIXES[i]) {
          return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: uri + '/' } }
          };
        }
      }

      return request;
    }
  EOT
}
