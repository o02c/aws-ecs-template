# --------------------------------------------------------------------------------
# CloudFront Signed URL — Key Material (dev: generate in-terraform for convenience)
# --------------------------------------------------------------------------------
# dev creates an RSA-2048 keypair each apply (tls_private_key is stateful so it
# persists across applies). The public PEM is fed to CloudFront; the private
# PEM is stored in Secrets Manager (KMS-encrypted) and read by ECS tasks at
# runtime. For prod, swap this block for external key material passed via
# `var.cloudfront_signing_public_key_pem` + `var.cloudfront_signing_key_secret_arn`
# so the private key never lives in terraform state.

resource "tls_private_key" "cloudfront_signing" {
  count = local.cloudfront_signing_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "cloudfront_signing" {
  count = local.cloudfront_signing_enabled ? 1 : 0

  name        = "${var.project_name}-${var.environment}-cloudfront-signing-key"
  description = "PEM-encoded RSA private key used to sign CloudFront URLs for ${var.project_name}-${var.environment}"
  kms_key_id  = module.kms.key_arns["secrets"]

  # dev: allow destroy without the default 7-30 day soft-delete window so
  # `just destroy` completes in one pass.
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-signing-key"
  }
}

resource "aws_secretsmanager_secret_version" "cloudfront_signing" {
  count = local.cloudfront_signing_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.cloudfront_signing[0].id
  secret_string = tls_private_key.cloudfront_signing[0].private_key_pem
}

locals {
  # Feature flag: when true, generate a keypair and enable CloudFront signing
  # on all lanes. Default true for dev; flip to false to skip entirely.
  cloudfront_signing_enabled = true

  # Resolve public key + secret ARN from either the generated keypair (dev)
  # or the variable-supplied material (prod override). The module's
  # `enable_signing` path keys off `public_key_pem != ""`.
  cloudfront_signing_public_key_pem = local.cloudfront_signing_enabled ? (
    tls_private_key.cloudfront_signing[0].public_key_pem
  ) : var.cloudfront_signing_public_key_pem

  cloudfront_signing_key_secret_arn = local.cloudfront_signing_enabled ? (
    aws_secretsmanager_secret.cloudfront_signing[0].arn
  ) : var.cloudfront_signing_key_secret_arn
}
