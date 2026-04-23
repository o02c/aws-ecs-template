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

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
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
      days          = var.access_log_lifecycle.transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.access_log_lifecycle.expiration_days
    }
  }
}

