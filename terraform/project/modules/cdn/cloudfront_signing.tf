# --------------------------------------------------------------------------------
# CloudFront Signing Key (for Signed URLs)
# --------------------------------------------------------------------------------

resource "aws_cloudfront_public_key" "signing" {
  for_each = var.enable_signing ? { "default" = true } : {}

  name        = "${var.project_name}-${var.environment}-${var.lane}-signing"
  encoded_key = var.signing_public_key_pem
  comment     = "Signing key for ${var.lane} signed URLs"
}

resource "aws_cloudfront_key_group" "signing" {
  for_each = var.enable_signing ? { "default" = true } : {}

  name    = "${var.project_name}-${var.environment}-${var.lane}-signing"
  items   = [aws_cloudfront_public_key.signing["default"].id]
  comment = "Key group for ${var.lane} signed URLs"
}
