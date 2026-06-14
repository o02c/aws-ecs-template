# --------------------------------------------------------------------------------
# S3 Bucket
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket              = "${var.project_name}-${var.environment}-${var.lane}-assets"
  object_lock_enabled = var.object_lock.enabled

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
# Object Lock (WORM) + version lifecycle
# --------------------------------------------------------------------------------
# Ransomware/tamper protection for front-end assets. default_retention applies to
# every object version; CI/CD overwrites create new (lockable) versions, so the
# noncurrent-version expiration must be longer than the WORM retention or the
# lifecycle delete would be blocked by the lock.

resource "aws_s3_bucket_object_lock_configuration" "this" {
  for_each = (
    var.object_lock.enabled &&
    var.object_lock.default_retention != null
  ) ? { this = true } : {}

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock.default_retention.mode
      days = var.object_lock.default_retention.days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-and-abort-mpu"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
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
