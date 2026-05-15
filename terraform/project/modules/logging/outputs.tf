output "bucket_id" {
  description = "Access log bucket ID"
  value       = aws_s3_bucket.access_logs.id
}

output "bucket_arn" {
  description = "Access log bucket ARN"
  value       = aws_s3_bucket.access_logs.arn
}

output "waf_bucket_id" {
  description = "WAF-dedicated log bucket ID"
  value       = aws_s3_bucket.waf_logs.id
}

output "waf_bucket_arn" {
  description = "WAF-dedicated log bucket ARN (passed to WAF logging configuration)"
  value       = aws_s3_bucket.waf_logs.arn
}

output "athena_workgroup_name" {
  description = "Athena workgroup name (used by scripts/athena-query.sh)"
  value       = aws_athena_workgroup.logs.name
}

output "athena_database_name" {
  description = "Glue catalog database name that holds Athena tables over the access logs"
  value       = aws_glue_catalog_database.logs.name
}

output "athena_results_bucket_id" {
  description = "Bucket holding Athena query result objects"
  value       = aws_s3_bucket.athena_results.id
}
