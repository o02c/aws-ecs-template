# --------------------------------------------------------------------------------
# Artifact S3 Bucket (Deploy Trigger Source)
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "artifact" {
  bucket = "${var.project_name}-${var.environment}-artifact"

  tags = {
    Name = "${var.project_name}-${var.environment}-artifact"
  }
}

resource "aws_s3_bucket_versioning" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  target_bucket = var.log_bucket_id
  target_prefix = "artifact/"
}

# --------------------------------------------------------------------------------
# SSL Enforcement
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "ssl_enforcement" {
  bucket = aws_s3_bucket.artifact.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.artifact.arn,
          "${aws_s3_bucket.artifact.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
