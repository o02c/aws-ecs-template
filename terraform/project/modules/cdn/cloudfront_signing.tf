# --------------------------------------------------------------------------------
# CloudFront Signing Key (for Signed URLs)
# --------------------------------------------------------------------------------
# Single signing key serves the default lane's S3 origin behind files_path_pattern.

resource "aws_cloudfront_public_key" "signing" {
  for_each = var.enable_signing ? { "default" = true } : {}

  name        = "${var.project_name}-${var.environment}-signing"
  encoded_key = var.signing_public_key_pem
  comment     = "Signing key for ${var.project_name}-${var.environment} signed URLs"
}

resource "aws_cloudfront_key_group" "signing" {
  for_each = var.enable_signing ? { "default" = true } : {}

  name    = "${var.project_name}-${var.environment}-signing"
  items   = [aws_cloudfront_public_key.signing["default"].id]
  comment = "Key group for ${var.project_name}-${var.environment} signed URLs"
}
