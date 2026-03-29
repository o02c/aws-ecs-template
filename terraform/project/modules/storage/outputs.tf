output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.this.id
}

output "bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "cloudfront_oac_id" {
  description = "CloudFront Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.this.id
}

output "s3_access_policy_arn" {
  description = "ARN of the S3 access IAM policy"
  value       = aws_iam_policy.s3_access.arn
}
