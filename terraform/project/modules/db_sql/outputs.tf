output "ddl_function_name" {
  description = "DDL Lambda function name (invoke target for schema-changing SQL)"
  value       = aws_lambda_function.ddl.function_name
}

output "dml_function_name" {
  description = "DML Lambda function name (invoke target for CRUD SQL)"
  value       = aws_lambda_function.dml.function_name
}

output "sql_bucket_id" {
  description = "Bucket name for staged SQL files (ddl/ and dml/ prefixes)"
  value       = aws_s3_bucket.sql.id
}

output "sql_bucket_arn" {
  description = "Bucket ARN (for IAM scoping of uploaders)"
  value       = aws_s3_bucket.sql.arn
}
