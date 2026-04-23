variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used in SNS topic policy conditions)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS topic encryption (service principal = cloudwatch.amazonaws.com)"
  type        = string
}

variable "alarm_recipients" {
  description = "Email addresses subscribed to both critical and warning SNS topics (Gmail manual confirm required)"
  type        = list(string)
}

variable "lanes" {
  description = "Lane names (e.g. user, admin) used for per-lane ALB alarms"
  type        = set(string)
}

variable "alb_arn_suffixes" {
  description = "Map of lane to ALB arn_suffix (from aws_lb.arn_suffix, used as CloudWatch dimension)"
  type        = map(string)
}

variable "target_group_arn_suffixes" {
  description = "Map of lane to target group arn_suffix"
  type        = map(string)
}

variable "ecs_cluster_name" {
  description = "ECS cluster name (CloudWatch dimension for per-service alarms)"
  type        = string
}

variable "ecs_service_names" {
  description = "Map of service identifier to ECS service name"
  type        = map(string)
}

variable "aurora_cluster_identifier" {
  description = "Aurora cluster identifier (CloudWatch dimension)"
  type        = string
}

variable "firehose_stream_names" {
  description = "Map of firehose stream kind (audit / ecs-logs) to stream name"
  type        = map(string)
}

variable "thresholds" {
  description = "Alarm thresholds (dev-lenient)"
  type = object({
    alb_5xx_count                = number
    aurora_cpu_percent           = number
    aurora_connections           = number
    ecs_running_gap_evaluations  = number
    alb_healthy_host_evaluations = number
  })
}
