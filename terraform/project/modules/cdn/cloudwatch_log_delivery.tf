# --------------------------------------------------------------------------------
# CloudWatch Logs Delivery — CloudFront Standard Logging v2 → S3 (Hive partitions)
# --------------------------------------------------------------------------------
# Only the *configuration* uses CW Logs APIs (PutDeliverySource /
# PutDeliveryDestination / CreateDelivery). Log data flows directly from
# CloudFront to S3 — nothing is stored in a CW Logs LogGroup, no CW Logs
# retention applies.
#
# CloudFront's legacy `logging_config` block delivers flat-prefix gzipped TSV
# objects (cloudfront/<distId>.YYYY-MM-DD-HH.UNIQUE.gz), which Athena cannot
# partition-prune on. Standard logging v2 writes to a partitioned layout that
# Athena's partition projection can target directly.
#
# Final S3 layout for this delivery:
#   s3://<bucket>/cloudfront/distributionid=<id>/year=YYYY/month=MM/day=DD/hour=HH/*.gz
#
# suffix_path uses bare variables ({yyyy} etc.); with enable_hive_compatible_path
# AWS auto-expands each to `year=<value>` / `month=<value>` / … . Using the
# lower-cased `{distributionid}` keeps the partition NAME lowercase so Glue
# (which our Athena DDL targets) accepts it. See:
# https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logging.html#partitioning
#
# The control-plane resources for CloudFront-scoped vended logs live in us-east-1
# (CloudFront is a global service whose CW Logs endpoint is anchored there).

resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  region = "us-east-1"

  name         = "${var.project_name}-${var.environment}-cloudfront"
  resource_arn = aws_cloudfront_distribution.this.arn
  log_type     = "ACCESS_LOGS"
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_s3" {
  region = "us-east-1"

  name          = "${var.project_name}-${var.environment}-cloudfront-s3"
  output_format = "plain"

  delivery_destination_configuration {
    # Prefix is included in the ARN so CloudFront does NOT auto-append the
    # `AWSLogs/{account-id}/CloudFront/` default; everything we want sits under
    # `cloudfront/` of the shared access-log bucket.
    destination_resource_arn = "${var.log_bucket_arn}/cloudfront"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-s3"
  }
}

resource "aws_cloudwatch_log_delivery" "cloudfront_s3" {
  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_s3.arn
  field_delimiter          = "\t"

  s3_delivery_configuration {
    enable_hive_compatible_path = true
    suffix_path                 = "{distributionid}/{yyyy}/{MM}/{dd}/{HH}"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-s3"
  }
}
