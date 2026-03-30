# --------------------------------------------------------------------------------
# CloudFront Origin Access Control
# --------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.project_name}-${var.environment}-${var.lane}"
  description                       = "OAC for ${var.lane} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
