# --------------------------------------------------------------------------------
# WAF Logging: direct S3 delivery (no us-east-1 Firehose needed)
# --------------------------------------------------------------------------------
# WAF logs go straight to the dedicated `aws-waf-logs-*` bucket in ap-northeast-1.
# The bucket name prefix (`aws-waf-logs-`) is an AWS requirement for direct-to-S3
# WAF logging. Bucket policy on the destination bucket authorizes the
# `delivery.logs.amazonaws.com` service principal from us-east-1 (CloudFront WAF
# source region). No Firehose resource is created in us-east-1.

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider = aws.us_east_1

  log_destination_configs = [var.waf_log_bucket_arn]
  resource_arn            = aws_wafv2_web_acl.this.arn
}
