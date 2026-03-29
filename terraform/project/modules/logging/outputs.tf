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
