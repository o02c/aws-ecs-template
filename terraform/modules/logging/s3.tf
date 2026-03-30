# --------------------------------------------------------------------------------
# Access Log Bucket
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_name}-${var.environment}-access-logs"

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
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# --------------------------------------------------------------------------------
# Bucket Policy
# --------------------------------------------------------------------------------

locals {
  # ELB account IDs per region for ALB access logging
  # https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
  elb_account_ids = {
    us-east-1      = "127311923021"
    us-east-2      = "033677994240"
    us-west-1      = "027434742980"
    us-west-2      = "797873946194"
    af-south-1     = "098369216593"
    ap-east-1      = "754344448648"
    ap-south-1     = "718504428378"
    ap-northeast-1 = "582318560864"
    ap-northeast-2 = "600734575887"
    ap-northeast-3 = "383597477331"
    ap-southeast-1 = "114774131450"
    ap-southeast-2 = "783225319266"
    ca-central-1   = "985666609251"
    eu-central-1   = "054676820928"
    eu-west-1      = "156460612806"
    eu-west-2      = "652711504416"
    eu-west-3      = "009996457667"
    eu-south-1     = "635631232127"
    eu-north-1     = "897822967062"
    me-south-1     = "076674570225"
    sa-east-1      = "507241528517"
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/cloudfront/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowCloudFrontLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.access_logs.arn
      },
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.elb_account_ids[var.region]}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/alb/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowS3LogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/s3/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowS3LogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.access_logs.arn
      }
    ]
  })
}
