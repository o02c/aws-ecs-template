# --------------------------------------------------------------------------------
# WAF Log Bucket (dedicated; AWS requires name to start with `aws-waf-logs-`)
# --------------------------------------------------------------------------------
# Cannot share with the access-logs bucket because WAF direct-to-S3 logging
# enforces the `aws-waf-logs-` prefix. Separate bucket is the cleanest path
# that keeps storage in ap-northeast-1 and avoids creating cross-region
# Firehose resources in us-east-1.

resource "aws_s3_bucket" "waf_logs" {
  bucket = "aws-waf-logs-${var.project_name}-${var.environment}-${var.aws_account_id}"

  tags = {
    Name = "aws-waf-logs-${var.project_name}-${var.environment}"
  }
}

resource "aws_s3_bucket_versioning" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

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
