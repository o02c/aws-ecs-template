output "artifact_bucket_name" {
  description = "Artifact S3 bucket name"
  value       = aws_s3_bucket.artifact.id
}

output "pipeline_arns" {
  description = "Map of service to CodePipeline ARN"
  value       = { for name, pipeline in aws_codepipeline.this : name => pipeline.arn }
}
