# --------------------------------------------------------------------------------
# WAF Logging: Firehose (us-east-1, required by CLOUDFRONT-scoped WAF) → S3 (ap-northeast-1)
# --------------------------------------------------------------------------------
# WAF log destination must be same-region as the Web ACL (us-east-1 for CloudFront).
# Firehose stream name must start with `aws-waf-logs-`. Destination bucket is the
# project's access-logs bucket in ap-northeast-1; Firehose supports cross-region S3.

resource "aws_iam_role" "waf_firehose" {
  provider = aws.us_east_1

  name = "${var.project_name}-${var.environment}-${var.lane}-waf-firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}-waf-firehose"
  }
}

resource "aws_iam_role_policy" "waf_firehose" {
  provider = aws.us_east_1

  name = "s3-access"
  role = aws_iam_role.waf_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        Resource = [
          var.log_bucket_arn,
          "${var.log_bucket_arn}/waf/${var.lane}/*",
          "${var.log_bucket_arn}/waf/${var.lane}-errors/*",
        ]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "waf" {
  provider = aws.us_east_1

  name        = "aws-waf-logs-${var.project_name}-${var.environment}-${var.lane}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.waf_firehose.arn
    bucket_arn = var.log_bucket_arn

    prefix              = "waf/${var.lane}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "waf/${var.lane}-errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = 60
    compression_format = "GZIP"
  }

  tags = {
    Name = "aws-waf-logs-${var.project_name}-${var.environment}-${var.lane}"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider = aws.us_east_1

  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn
}
