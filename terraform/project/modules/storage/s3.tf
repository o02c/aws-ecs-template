# --------------------------------------------------------------------------------
# S3 Bucket
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = "${var.project_name}-${var.environment}-${var.lane}-assets"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}-assets"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------------
# Access Logging
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket_id
  target_prefix = var.log_prefix
}

# NOTE: SSL enforcement + CloudFront OAC are merged into a single bucket policy
# in the cdn module (terraform/project/modules/cdn/s3_bucket_policy.tf).
# S3 allows only one bucket policy per bucket — having two aws_s3_bucket_policy
# resources targeting the same bucket causes last-writer-wins and silently
# drops whichever statement loses the race.
