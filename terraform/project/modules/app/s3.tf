# --------------------------------------------------------------------------------
# S3 Bucket: app resources (startup config + report templates + master data)
# --------------------------------------------------------------------------------
# Single bucket shared by all lanes; lane isolation is enforced at the IAM
# policy layer (see task_app_resources in iam.tf). Layout:
#   common/...    shared across lanes
#   <lane>/...    readable only by that lane's task role (e.g. user/, admin/)
# ECS tasks read only; deployments lay down files via CI/CD or operator upload.

resource "aws_s3_bucket" "app_resources" {
  bucket = "${var.project_name}-${var.environment}-app-resources"

  tags = {
    Name = "${var.project_name}-${var.environment}-app-resources"
  }
}

resource "aws_s3_bucket_versioning" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.s3_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are disabled entirely — bucket-owner-enforced object ownership matches the
# read-only, ECS-only access pattern (no AWS service log delivery, no cross-acct
# writers). Aligns with logging/s3_athena_results.tf.
resource "aws_s3_bucket_ownership_controls" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "app_resources" {
  bucket        = aws_s3_bucket.app_resources.id
  target_bucket = var.log_bucket_id
  target_prefix = "s3/app-resources/"

  # Date-partitioned keys for Athena (matches Firehose/VPC-flow layout).
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# Current versions are retained forever (templates/config evolve under git+CI).
# Noncurrent versions accumulate fast on file rewrites — expire after 90 days
# so the bucket doesn't bloat. Abort orphaned multipart uploads after a week.
resource "aws_s3_bucket_lifecycle_configuration" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  rule {
    id     = "expire-noncurrent-and-abort-mpu"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "app_resources" {
  bucket = aws_s3_bucket.app_resources.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.app_resources.arn,
          "${aws_s3_bucket.app_resources.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}
