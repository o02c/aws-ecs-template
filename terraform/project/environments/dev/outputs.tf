# --------------------------------------------------------------------------------
# ecspresso References
# --------------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.app.ecr_repository_urls
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.app.task_execution_role_arn
}

output "task_role_arns" {
  description = "Map of service name to task role ARN"
  value       = module.app.task_role_arns
}

output "target_group_arns" {
  description = "Map of lane to target group ARN"
  value       = { for lane, lb in module.lb : lane => lb.target_group_arn }
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = module.network.security_group_ids["ecs"]
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value       = module.network.private_subnet_ids
}

output "s3_bucket_ids" {
  description = "Map of lane to S3 bucket ID"
  value       = { for lane, s in module.storage : lane => s.bucket_id }
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.app.ecs_cluster_name
}

output "nginx_ecr_repository_url" {
  description = "nginx ECR repository URL"
  value       = module.app.nginx_ecr_repository_url
}

output "ecr_public_cache_base_uri" {
  description = "Base URI of the ECR pull-through cache for public.ecr.aws (consumers append <namespace>/<repo>:<tag>)"
  value       = module.app.ecr_public_cache_base_uri
}

output "fluent_bit_config_s3_arn" {
  description = "S3 ARN of Fluent Bit extra config"
  value       = module.app.fluent_bit_config_s3_arn
}

output "fluent_bit_parsers_s3_arn" {
  description = "S3 ARN of optional Fluent Bit parsers (python_json, nginx, nginx_json)"
  value       = module.app.fluent_bit_parsers_s3_arn
}


output "domain_name" {
  description = "Single public FQDN (all lanes share this; path_prefix selects the lane)"
  value       = var.domain_name
}

output "lane_url_prefixes" {
  description = "Map of lane to base URL (https://<domain><path_prefix>); consumers append /api/health etc."
  value = {
    for lane, cfg in local.lanes :
    lane => "https://${var.domain_name}${cfg.path_prefix}"
  }
}

output "lane_path_prefixes" {
  description = "Map of lane to URL path prefix (\"\" for default, e.g. \"/admin\")"
  value       = { for lane, cfg in local.lanes : lane => cfg.path_prefix }
}

output "firehose_stream_names" {
  description = "Map of firehose stream kind (audit / ecs-logs) to stream name"
  value       = module.app.firehose_stream_names
}

# --------------------------------------------------------------------------------
# SES (consumed by ECS task def env vars)
# --------------------------------------------------------------------------------

output "ses_sender_address" {
  description = "Default sender address for SES SendEmail (empty if email disabled)"
  value       = local.email.enabled ? one([for _, m in module.email : m.sender_address]) : ""
}

output "ses_verified_recipients_csv" {
  description = "Comma-separated list of verified recipients for the app's allowlist (empty if email disabled)"
  value       = local.email.enabled ? join(",", local.email.verified_recipients) : ""
}

output "sns_alarm_topic_arns" {
  description = "Map of severity to SNS alarm topic ARN"
  value       = module.monitoring.topic_arns
}

# --------------------------------------------------------------------------------
# CloudFront Signed URL (consumed by ECS task def env vars)
# --------------------------------------------------------------------------------

output "cloudfront_signing_key_pair_id" {
  description = "CloudFront signing key pair ID (single distribution; empty if signing disabled)"
  value       = module.cdn.signing_key_pair_id
}

output "cloudfront_signing_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the signing private key (empty if disabled)"
  value       = local.cloudfront_signing_key_secret_arn
}

# --------------------------------------------------------------------------------
# Athena / log analysis (consumed by scripts/athena-query.sh)
# --------------------------------------------------------------------------------

output "access_log_bucket_id" {
  description = "Shared access-log bucket (CloudFront/ALB/S3/Firehose logs land here under prefixes — see docs/logs.md)"
  value       = module.logging.bucket_id
}

output "athena_workgroup_name" {
  description = "Athena workgroup that pins query result storage and metrics"
  value       = module.logging.athena_workgroup_name
}

output "athena_database_name" {
  description = "Glue catalog database for access-log Athena tables"
  value       = module.logging.athena_database_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (also surfaces as the `distributionid` partition value in cloudfront_logs)"
  value       = module.cdn.distribution_id
}
