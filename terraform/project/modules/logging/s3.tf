# --------------------------------------------------------------------------------
# Access Log Bucket
# --------------------------------------------------------------------------------
# ALB / CloudFront / S3 server access / Firehose (audit, ecs-logs-app, ecs-logs-nginx) / VPC Flow Logs
# を prefix ごとに集約。lifecycle は lifecycle.tf で log_retention map から生成。
# Object Lock の on/off は var.log_buckets.access_logs.object_lock で制御。
# enabled=true への切替はバケット recreate を伴うため要注意 (不可逆)。

resource "aws_s3_bucket" "access_logs" {
  bucket              = "${var.project_name}-${var.environment}-access-logs-${var.aws_account_id}"
  object_lock_enabled = var.log_buckets.access_logs.object_lock.enabled

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

resource "aws_s3_bucket_object_lock_configuration" "access_logs" {
  count = (
    var.log_buckets.access_logs.object_lock.enabled &&
    var.log_buckets.access_logs.object_lock.default_retention != null
  ) ? 1 : 0

  bucket = aws_s3_bucket.access_logs.id

  rule {
    default_retention {
      mode = var.log_buckets.access_logs.object_lock.default_retention.mode
      days = var.log_buckets.access_logs.object_lock.default_retention.days
    }
  }
}
