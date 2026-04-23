output "bucket_id" {
  description = "Access log bucket ID"
  value       = aws_s3_bucket.access_logs.id
}

output "bucket_arn" {
  description = "Access log bucket ARN"
  value       = aws_s3_bucket.access_logs.arn
}

output "bucket_domain_name" {
  description = "Access log bucket domain name"
  value       = aws_s3_bucket.access_logs.bucket_domain_name
}

output "waf_bucket_id" {
  description = "WAF-dedicated log bucket ID"
  value       = aws_s3_bucket.waf_logs.id
}

output "waf_bucket_arn" {
  description = "WAF-dedicated log bucket ARN (passed to WAF logging configuration)"
  value       = aws_s3_bucket.waf_logs.arn
}
