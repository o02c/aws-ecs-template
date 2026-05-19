output "cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "cluster_identifier" {
  description = "Aurora cluster identifier (CloudWatch dimension)"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_resource_id" {
  description = "Aurora cluster resource ID"
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "rds_iam_auth_policy_arn" {
  description = "ARN of the RDS IAM authentication policy"
  value       = aws_iam_policy.rds_iam_auth.arn
}

output "master_user_secret_arn" {
  description = "ARN of the AWS-managed master user Secrets Manager secret"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "database_name" {
  description = "Initial database name"
  value       = aws_rds_cluster.this.database_name
}
