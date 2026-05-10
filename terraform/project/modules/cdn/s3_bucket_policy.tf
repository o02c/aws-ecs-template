# --------------------------------------------------------------------------------
# S3 Bucket Policy (CloudFront OAC + SSL enforcement, per-lane bucket)
# --------------------------------------------------------------------------------
# Each lane's asset bucket gets a single policy combining the OAC GetObject
# allow and the SSL-only deny. The single distribution ARN is the SourceArn
# for every lane's bucket.

resource "aws_s3_bucket_policy" "this" {
  for_each = var.lanes

  bucket = each.value.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${each.value.s3_bucket_id}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${each.value.s3_bucket_id}",
          "arn:aws:s3:::${each.value.s3_bucket_id}/*",
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
