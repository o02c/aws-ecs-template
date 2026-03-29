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
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------------
# EventBridge Notification
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "artifact" {
  bucket      = aws_s3_bucket.artifact.id
  eventbridge = true
}
