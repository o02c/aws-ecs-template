# --------------------------------------------------------------------------------
# CloudFront Function: maintenance gate + trailing-slash + lane-prefix handling
# --------------------------------------------------------------------------------
# Single viewer-request function on the S3-origin (frontend) behaviors. CloudFront
# allows only one function per event type per behavior, so all logic lives here:
#
#   0. Maintenance gate — if KVS key `maintenance` == "on", return a 503 page,
#      UNLESS the viewer IP matches the KVS key `maintenance_allow` (an optional
#      comma-separated list of IPv4 addresses / CIDRs that bypass the gate, e.g.
#      ops during a manual maintenance window). Absent/empty list => no bypass.
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

    // IPv4 dotted-quad -> uint32, or null for non-IPv4 (e.g. IPv6 viewer.ip).
    // Octets must be plain digit strings (rejects "0x1", "1e2", " 5", "") so a
    // malformed entry never widens the match.
    function ipToInt(ip) {
      var p = ip.split('.');
      if (p.length !== 4) return null;
      var n = 0;
      for (var i = 0; i < 4; i++) {
        if (!/^[0-9]{1,3}$/.test(p[i])) return null;
        var o = Number(p[i]);
        if (o > 255) return null;
        n = (n * 256) + o;
      }
      return n >>> 0;
    }

    // Match viewer IP against a list of exact IPs / IPv4 CIDRs (e.g. "1.2.3.4",
    // "203.0.113.0/24"). Exact entries also match IPv6 by string equality.
    // A malformed entry is skipped (fail closed), never treated as allow-all.
    function ipAllowed(ip, list) {
      var v = ipToInt(ip);
      for (var i = 0; i < list.length; i++) {
        var e = list[i].trim();
        if (!e) continue;
        var slash = e.indexOf('/');
        if (slash === -1) { if (e === ip) return true; continue; }
        if (v === null) continue;
        var base = ipToInt(e.slice(0, slash));
        var bitsStr = e.slice(slash + 1);
        if (base === null || !/^[0-9]{1,2}$/.test(bitsStr)) continue;
        var bits = Number(bitsStr);
        if (bits > 32) continue;
        var mask = bits === 0 ? 0 : (0xFFFFFFFF << (32 - bits)) >>> 0;
        if (((v & mask) >>> 0) === ((base & mask) >>> 0)) return true;
      }
      return false;
    }

    async function handler(event) {
      var request = event.request;
      var uri = request.uri;

      try {
        if ((await kvs.get('maintenance')) === 'on') {
          var allow = '';
          try { allow = await kvs.get('maintenance_allow'); } catch (e) { allow = ''; }
          if (!ipAllowed(event.viewer.ip, allow ? allow.split(',') : [])) {
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
