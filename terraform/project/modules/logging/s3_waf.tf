# --------------------------------------------------------------------------------
# WAF Log Bucket (dedicated; AWS requires name to start with `aws-waf-logs-`)
# --------------------------------------------------------------------------------
# Cannot share with the access-logs bucket because WAF direct-to-S3 logging
# enforces the `aws-waf-logs-` prefix. Separate bucket is the cleanest path
# that keeps storage in ap-northeast-1 and avoids creating cross-region
# Firehose resources in us-east-1.

resource "aws_s3_bucket" "waf_logs" {
  bucket              = "aws-waf-logs-${var.project_name}-${var.environment}-${var.aws_account_id}"
  object_lock_enabled = var.log_buckets.waf_logs.object_lock.enabled

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

resource "aws_s3_bucket_object_lock_configuration" "waf_logs" {
  count = (
    var.log_buckets.waf_logs.object_lock.enabled &&
    var.log_buckets.waf_logs.object_lock.default_retention != null
  ) ? 1 : 0

  bucket = aws_s3_bucket.waf_logs.id

  rule {
    default_retention {
      mode = var.log_buckets.waf_logs.object_lock.default_retention.mode
      days = var.log_buckets.waf_logs.object_lock.default_retention.days
    }
  }
}
