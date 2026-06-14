# --------------------------------------------------------------------------------
# ELB Service Account (for ALB access log delivery)
# --------------------------------------------------------------------------------
# aws_elb_service_account returns the per-region ELB log-delivery account.
# Avoid hardcoding the region→account map; the data source follows AWS updates.

data "aws_elb_service_account" "this" {}

# --------------------------------------------------------------------------------
# Bucket Policy
# --------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudFront standard logging v2 → S3 (vended logs).
      # SourceAccount/SourceArn pin the delivery-source ARN to this account in
      # us-east-1, matching the AWS-recommended vended-logs S3 policy template.
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
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = [var.aws_account_id]
          }
          ArnLike = {
            "aws:SourceArn" = ["arn:aws:logs:us-east-1:${var.aws_account_id}:delivery-source:*"]
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
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = [var.aws_account_id]
          }
          ArnLike = {
            "aws:SourceArn" = ["arn:aws:logs:us-east-1:${var.aws_account_id}:delivery-source:*"]
          }
        }
      },
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.this.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/alb/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      # NOTE: unlike ALB/CloudFront/VPC-flow delivery, the S3 server-access-log
      # service (logging.s3.amazonaws.com) does NOT send an x-amz-acl header, so
      # an "s3:x-amz-acl = bucket-owner-full-control" condition here silently
      # blocks delivery. Scope by SourceAccount only (matches the AWS console's
      # auto-generated policy).
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
            "aws:SourceAccount" = [var.aws_account_id]
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
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = [var.aws_account_id]
          }
        }
      },
      # VPC Flow Logs S3 direct delivery (parquet + hive). AWS uses the same
      # delivery.logs.amazonaws.com vended-logs principal as CloudFront /
      # CloudWatch Logs delivery, scoped to vpc-flow/ prefix.
      {
        Sid    = "AllowVPCFlowLogsDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/vpc-flow/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = [var.aws_account_id]
          }
        }
      },
      {
        Sid    = "AllowVPCFlowLogsAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.access_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = [var.aws_account_id]
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.access_logs.arn,
          "${aws_s3_bucket.access_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
