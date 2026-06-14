# --------------------------------------------------------------------------------
# SQL Staging Bucket
# --------------------------------------------------------------------------------
# Long-form SQL (anything that doesn't fit cleanly in a Lambda invoke payload)
# is uploaded here under ddl/ or dml/ prefixes. Each Lambda's IAM role is
# scoped to its own prefix (iam.tf) so an upload to the wrong prefix is a no-op.

resource "aws_s3_bucket" "sql" {
  bucket = "${var.project_name}-${var.environment}-db-sql-${var.aws_account_id}"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sql"
  }
}

resource "aws_s3_bucket_versioning" "sql" {
  bucket = aws_s3_bucket.sql.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sql" {
  bucket = aws_s3_bucket.sql.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.secrets_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "sql" {
  bucket = aws_s3_bucket.sql.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sql" {
  bucket = aws_s3_bucket.sql.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "sql" {
  bucket        = aws_s3_bucket.sql.id
  target_bucket = var.log_bucket_id
  target_prefix = "s3/db-sql/"

  # Date-partitioned keys for Athena (matches Firehose/VPC-flow layout).
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_policy" "sql" {
  bucket = aws_s3_bucket.sql.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.sql.arn,
          "${aws_s3_bucket.sql.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "sql" {
  bucket = aws_s3_bucket.sql.id

  rule {
    id     = "sql-files"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
