# --------------------------------------------------------------------------------
# WAF Log Bucket Policy
# --------------------------------------------------------------------------------
# WAF (scope=CLOUDFRONT) uses the CloudWatch log-delivery service principal to
# write to S3. Source region is us-east-1 because CloudFront-scoped Web ACLs
# live there. aws:SourceAccount pins ownership; aws:SourceArn pins delivery
# origin region so only our own CloudFront WAF logs can land here.

resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = [var.aws_account_id]
          }
          ArnLike = {
            "aws:SourceArn" = ["arn:aws:logs:us-east-1:${var.aws_account_id}:*"]
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.waf_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = [var.aws_account_id]
          }
          ArnLike = {
            "aws:SourceArn" = ["arn:aws:logs:us-east-1:${var.aws_account_id}:*"]
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.waf_logs.arn,
          "${aws_s3_bucket.waf_logs.arn}/*",
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
