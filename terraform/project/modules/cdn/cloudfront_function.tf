# --------------------------------------------------------------------------------
# CloudFront Function: maintenance gate + trailing-slash + lane-prefix handling
# --------------------------------------------------------------------------------
# Single viewer-request function on the S3-origin (frontend) behaviors. CloudFront
# allows only one function per event type per behavior, so all logic lives here:
#
#   0. Maintenance gate — if KVS key `maintenance` == "on", return a 503 page.
#      Covers the frontend only; the ALB/API behaviors are intentionally left
#      ungated because the power_schedule module scales ECS to 0 during the same
#      window, so the origin is already down. Fails open on any KVS error.
#   1. URI ending with `/`  → append `index.html` (e.g. /admin/ → /admin/index.html)
#   2. URI exactly equal to a non-default lane prefix → 301 to `<uri>/` (e.g.
#      /admin → /admin/), so the browser settles on the canonical form before
#      rule 1 fires on the redirect target.
#
# Runtime 2.0 is required for KVS access (async handler). Code + the embedded HTML
# must stay under the 10 KB function-size limit, so maintenance.html is kept small.
# Free tier: 2M invocations/month.

locals {
  lane_redirect_prefixes = [for k, v in var.lanes : v.path_prefix if v.path_prefix != ""]
}

resource "aws_cloudfront_function" "rewrite_index" {
  name    = "${var.project_name}-${var.environment}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  comment = "Maintenance gate (KVS) + trailing-slash → index.html + lane-prefix redirect"
  publish = true

  key_value_store_associations = [aws_cloudfront_key_value_store.maintenance.arn]

  code = <<-EOT
    import cf from 'cloudfront';

    var LANE_PREFIXES = ${jsonencode(local.lane_redirect_prefixes)};
    var MAINTENANCE_HTML = ${jsonencode(file("${path.module}/maintenance.html"))};
    var kvs = cf.kvs();

    async function handler(event) {
      var request = event.request;
      var uri = request.uri;

      try {
        if ((await kvs.get('maintenance')) === 'on') {
          return {
            statusCode: 503,
            statusDescription: 'Service Unavailable',
            headers: {
              'content-type':  { value: 'text/html; charset=UTF-8' },
              'cache-control': { value: 'no-cache, no-store, must-revalidate' },
              'retry-after':   { value: '3600' }
            },
            body: MAINTENANCE_HTML
          };
        }
      } catch (e) {}

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
