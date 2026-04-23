locals {
  aws_region  = "ap-northeast-1"
  vpc_cidr    = var.vpc_cidr
  name_prefix = "${var.project_name}-${var.environment}"

  # VPC flow log CloudWatch retention (days)
  flow_log_retention_days = 30

  # Access-log bucket lifecycle (covers ALB/CloudFront/S3/audit/ecs-logs/waf prefixes).
  # dev は短期保持、prod は規制要件に合わせて長期化。
  access_log_lifecycle = {
    transition_days = 90
    expiration_days = 365
  }

  # CloudFront static-assets cache TTL
  cache_ttl = {
    default_seconds = 86400    # 1 day
    max_seconds     = 31536000 # 1 year
  }

  # Firehose audit-log delivery buffering
  firehose_buffering_interval_seconds = 60

  # ALB idle timeout (connection keep-alive budget)
  alb_idle_timeout_seconds = 60

  # ALB target group tuning
  lb_target_group = {
    deregistration_delay_seconds = 30
    health_check = {
      path                = "/health"
      healthy_threshold   = 2
      unhealthy_threshold = 3
      timeout_seconds     = 5
      interval_seconds    = 30
    }
  }

  # Container port (ECS → ALB target group)
  container_port = 80

  # CloudFront WAF rate limit (requests per 5-min per IP)
  waf_rate_limit = 2000

  # CloudFront geo restriction (ISO 3166-1 alpha-2 whitelist)
  geo_restriction_locations = ["JP"]

  # Signed URL path pattern (for CloudFront signing feature)
  signed_files_path_pattern = "/files/*"

  # Email (SES sandbox). Set enabled = false to skip all SES / Route53 records.
  # After apply, verify_recipients receive a confirmation email from AWS that
  # must be clicked manually in Gmail. The domain DKIM is auto-verified.
  email = {
    enabled             = true
    sender_address      = "no-reply@o2c.click"
    mail_from_subdomain = "bounce"
    verified_recipients = ["ohtsuka.kentaro.o2c@gmail.com"]
    dmarc_rua_address   = "postmaster@o2c.click"
  }

  # CloudWatch Alarm → SNS → Email
  # Recipients must confirm the SNS subscription email from AWS (Gmail manual click).
  alarm_recipients = ["ohtsuka.kentaro.o2c@gmail.com"]

  alarm_thresholds = {
    alb_5xx_count                = 5
    aurora_cpu_percent           = 80
    aurora_connections           = 40
    ecs_running_gap_evaluations  = 5 # 1min × 5 = 5min sustained
    alb_healthy_host_evaluations = 5 # 2min × 5 = 10min sustained
  }

  # Aurora PostgreSQL cluster config. Change these to tune per env.
  db_config = {
    engine_version          = "16.4"
    database_name           = "app"
    iam_username            = "app"
    instances               = { writer = {}, reader = {} }
    serverless_min_capacity = 0.5
    serverless_max_capacity = 4
    backup_retention_period = 7
    deletion_protection     = false
    skip_final_snapshot     = true
  }

  # KMS keys managed at the project state layer. Used by Aurora / S3 / CloudWatch /
  # Secrets Manager for this project. shared 側と同名 key (logs) があっても、
  # それぞれ別の state で別の resource 群を暗号化している（§8）。
  kms_keys = {
    rds = {
      description = "CMK for Aurora encryption"
      service     = null
    }
    s3 = {
      description = "CMK for S3 bucket encryption"
      service     = null
    }
    logs = {
      description = "CMK for CloudWatch Logs encryption"
      service     = "logs.${local.aws_region}.amazonaws.com"
    }
    secrets = {
      description = "CMK for Secrets Manager encryption"
      service     = null
    }
    sns = {
      description = "CMK for SNS topic encryption (CloudWatch Alarm publishes)"
      service     = "cloudwatch.amazonaws.com"
    }
  }

  lanes = {
    user  = {}
    admin = {}
  }

  azs = ["${local.aws_region}a", "${local.aws_region}c"]

  private_subnets = {
    "${local.aws_region}a" = cidrsubnet(local.vpc_cidr, 8, 11)
    "${local.aws_region}c" = cidrsubnet(local.vpc_cidr, 8, 12)
  }

  security_groups = toset(concat(
    ["ecs", "db"],
    [for lane in keys(local.lanes) : "${lane}-alb"]
  ))

  # S3 gateway endpoint retained (free, better performance)
  gateway_endpoints = {
    s3 = "com.amazonaws.${local.aws_region}.s3"
  }

  # Transit Gateway ID from shared state
  transit_gateway_id = data.terraform_remote_state.shared.outputs.transit_gateway_id

  services = {
    user-api  = { lane = "user" }
    admin-api = { lane = "admin" }
  }
}
