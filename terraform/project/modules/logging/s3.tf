# --------------------------------------------------------------------------------
# Access Log Bucket
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_name}-${var.environment}-access-logs-${var.aws_account_id}"

  tags = {
    Name = "${var.project_name}-${var.environment}-access-logs"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  # CloudFront standard logging requires ACL-based delivery (bucket-owner-full-control).
  # block_public_acls must be false to allow this. Access is restricted via bucket policy.
  block_public_acls       = false
  block_public_policy     = true
  # CloudFront standard logging requires ACL-based delivery (bucket-owner-full-control).
  # ignore_public_acls must be false to allow this. Access is restricted via bucket policy.
  ignore_public_acls      = false
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------------
# Lifecycle Rule
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

