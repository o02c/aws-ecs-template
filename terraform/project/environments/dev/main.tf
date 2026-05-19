# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# --------------------------------------------------------------------------------
# Shared Infrastructure State
# --------------------------------------------------------------------------------

data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = var.shared_state_bucket
    key    = var.shared_state_key
    region = local.aws_region
  }
}

# --------------------------------------------------------------------------------
# KMS
# --------------------------------------------------------------------------------

module "kms" {
  source = "../../modules/kms"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = local.aws_region
  keys           = local.kms_keys
}

# --------------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------------

module "logging" {
  source = "../../modules/logging"

  project_name   = var.project_name
  environment    = var.environment
  region         = local.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  log_retention  = local.log_retention
  log_buckets    = local.log_buckets
}

# --------------------------------------------------------------------------------
# Network
# --------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name                 = var.project_name
  environment                  = var.environment
  vpc_cidr                     = local.vpc_cidr
  private_subnets              = local.private_subnets
  security_groups              = local.security_groups
  gateway_endpoints            = local.gateway_endpoints
  shared_endpoint_phz_zone_ids = data.terraform_remote_state.shared.outputs.endpoint_phz_zone_ids
  transit_gateway_id           = local.transit_gateway_id
  kms_key_arn                  = module.kms.key_arns["logs"]
  access_logs_bucket_arn       = module.logging.bucket_arn
  vpc_flow_log_retention       = local.log_retention.vpc_flow
}

# --------------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------------

module "db" {
  source = "../../modules/db"

  project_name          = var.project_name
  environment           = var.environment
  aws_account_id        = data.aws_caller_identity.current.account_id
  aws_region            = local.aws_region
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  db_security_group_id  = module.network.security_group_ids["db"]
  ecs_security_group_id = module.network.security_group_ids["ecs"]

  master_username = var.db_master_username
  kms_key_arn     = module.kms.key_arns["rds"]

  db_config = local.db_config
}

# --------------------------------------------------------------------------------
# DB SQL Runner (out-of-band SQL execution: DDL bootstrap + ad-hoc DML)
# --------------------------------------------------------------------------------

module "db_sql" {
  source = "../../modules/db_sql"

  project_name             = var.project_name
  environment              = var.environment
  aws_account_id           = data.aws_caller_identity.current.account_id
  aws_region               = local.aws_region
  vpc_id                   = module.network.vpc_id
  private_subnet_ids       = module.network.private_subnet_ids
  db_sql_security_group_id = module.network.security_group_ids["db-sql"]
  db_security_group_id     = module.network.security_group_ids["db"]
  db_host                  = module.db.cluster_endpoint
  db_name                  = module.db.database_name
  db_cluster_resource_id   = module.db.cluster_resource_id
  master_username          = var.db_master_username
  master_user_secret_arn   = module.db.master_user_secret_arn
  dml_username             = local.db_sql.dml_username
  secrets_kms_key_arn      = module.kms.key_arns["secrets"]
  rds_kms_key_arn          = module.kms.key_arns["rds"]
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_bucket_id            = module.logging.bucket_id
  log_retention_days       = local.db_sql.log_retention_days

  shared_private_subnet_cidrs = data.terraform_remote_state.shared.outputs.shared_private_subnet_cidrs
  s3_prefix_list_id           = module.network.s3_prefix_list_id
}

# --------------------------------------------------------------------------------
# Load Balancer (per-lane)
# --------------------------------------------------------------------------------

module "lb" {
  source   = "../../modules/lb"
  for_each = local.lanes

  project_name          = var.project_name
  environment           = var.environment
  lane                  = each.key
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.security_group_ids["${each.key}-alb"]
  ecs_security_group_id = module.network.security_group_ids["ecs"]
  acm_certificate_arn   = module.cert.regional_certificate_arn
  idle_timeout_seconds  = local.alb_idle_timeout_seconds
  container_port        = local.container_port
  target_group          = local.lb_target_group
  log_bucket_id         = module.logging.bucket_id
  log_prefix            = "alb/${each.key}"
}

# --------------------------------------------------------------------------------
# Storage (per-lane)
# --------------------------------------------------------------------------------

module "storage" {
  source   = "../../modules/storage"
  for_each = local.lanes

  project_name  = var.project_name
  environment   = var.environment
  lane          = each.key
  kms_key_arn   = module.kms.key_arns["s3"]
  log_bucket_id = module.logging.bucket_id
  log_prefix    = "s3/${each.key}/"
}

# --------------------------------------------------------------------------------
# Application
# --------------------------------------------------------------------------------

module "app" {
  source = "../../modules/app"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  ecs_security_group_id = module.network.security_group_ids["ecs"]
  alb_security_group_ids = {
    for lane in keys(local.lanes) : lane => module.network.security_group_ids["${lane}-alb"]
  }
  db_security_group_id        = module.network.security_group_ids["db"]
  shared_private_subnet_cidrs = data.terraform_remote_state.shared.outputs.shared_private_subnet_cidrs
  s3_prefix_list_id           = module.network.s3_prefix_list_id
  db_cluster_arn              = module.db.cluster_arn
  db_resource_id              = module.db.cluster_resource_id
  services                    = local.services
  s3_bucket_arns = {
    for lane, mod in module.storage : lane => mod.bucket_arn
  }
  rds_iam_auth_policy_arn = module.db.rds_iam_auth_policy_arn
  s3_access_policy_arns = {
    for lane, mod in module.storage : lane => mod.s3_access_policy_arn
  }
  cloudfront_signing_enabled          = local.cloudfront_signing_enabled
  cloudfront_signing_key_secret_arn   = local.cloudfront_signing_key_secret_arn
  secrets_kms_key_arn                 = module.kms.key_arns["secrets"]
  logs_kms_key_arn                    = module.kms.key_arns["logs"]
  aws_account_id                      = data.aws_caller_identity.current.account_id
  aws_region                          = local.aws_region
  s3_kms_key_arn                      = module.kms.key_arns["s3"]
  log_bucket_id                       = module.logging.bucket_id
  container_port                      = local.container_port
  firehose_buffering_interval_seconds = local.firehose_buffering_interval_seconds
  fluent_bit_log_retention            = local.log_retention.fluent_bit
  email_enabled                       = local.email.enabled
  email_policy_arn                    = local.email.enabled ? one([for _, m in module.email : m.policy_arn]) : ""
}

# --------------------------------------------------------------------------------
# Email (SES, optional)
# --------------------------------------------------------------------------------

module "email" {
  source   = "../../modules/email"
  for_each = local.email.enabled ? { this = true } : {}

  project_name        = var.project_name
  environment         = var.environment
  domain_name         = var.domain_name
  route53_zone_id     = module.dns.zone_id
  mail_from_subdomain = local.email.mail_from_subdomain
  sender_address      = local.email.sender_address
  verified_recipients = local.email.verified_recipients
  dmarc_rua_address   = local.email.dmarc_rua_address
}

# --------------------------------------------------------------------------------
# Monitoring (SNS + CloudWatch Alarms)
# --------------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  project_name              = var.project_name
  environment               = var.environment
  aws_account_id            = data.aws_caller_identity.current.account_id
  aws_region                = local.aws_region
  kms_key_arn               = module.kms.key_arns["sns"]
  alarm_recipients          = local.alarm_recipients
  lanes                     = toset(keys(local.lanes))
  alb_arn_suffixes          = { for lane, lb in module.lb : lane => lb.alb_arn_suffix }
  target_group_arn_suffixes = { for lane, lb in module.lb : lane => lb.target_group_arn_suffix }
  ecs_cluster_name          = module.app.ecs_cluster_name
  ecs_service_names         = { for k, _ in local.services : k => k }
  aurora_cluster_identifier = module.db.cluster_identifier
  firehose_stream_names     = module.app.firehose_stream_names
  thresholds                = local.alarm_thresholds
}

# --------------------------------------------------------------------------------
# CDN (single distribution, path-routed across lanes)
# --------------------------------------------------------------------------------

module "cdn" {
  source = "../../modules/cdn"

  project_name = var.project_name
  environment  = var.environment

  lanes = {
    for lane, cfg in local.lanes : lane => {
      path_prefix                    = cfg.path_prefix
      alb_arn                        = module.lb[lane].alb_arn
      alb_dns_name                   = module.lb[lane].alb_dns_name
      alb_security_group_id          = module.network.security_group_ids["${lane}-alb"]
      s3_bucket_regional_domain_name = module.storage[lane].bucket_regional_domain_name
      s3_bucket_id                   = module.storage[lane].bucket_id
      cloudfront_oac_id              = module.storage[lane].cloudfront_oac_id
    }
  }

  acm_certificate_arn       = module.cert.cloudfront_certificate_arn
  hostname                  = var.domain_name
  route53_zone_id           = module.dns.zone_id
  enable_signing            = local.cloudfront_signing_enabled
  signing_public_key_pem    = local.cloudfront_signing_public_key_pem
  files_path_pattern        = local.signed_files_path_pattern
  waf_rate_limit            = local.waf_rate_limit
  ip_allowlist              = local.ip_allowlist
  geo_restriction_locations = local.geo_restriction_locations
  cache_ttl                 = local.cache_ttl
  log_bucket_arn            = module.logging.bucket_arn
  waf_log_bucket_arn        = module.logging.waf_bucket_arn
  vpc_id                    = module.network.vpc_id
}

# --------------------------------------------------------------------------------
# DNS (Route53 hosted zone + registrar NS sync)
# --------------------------------------------------------------------------------
# Lifecycle note: zone is created first so its name servers can be propagated to
# the domain registrar. ACM certificates (module.cert) depend on that delegation
# being in place for DNS validation to succeed.

module "dns" {
  source = "../../modules/dns"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
}

# --------------------------------------------------------------------------------
# Certificates (ACM regional + CloudFront)
# --------------------------------------------------------------------------------

module "cert" {
  source = "../../modules/cert"

  project_name    = var.project_name
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = module.dns.zone_id
}

# --------------------------------------------------------------------------------
# DNS Firewall (disabled - cost vs benefit consideration for private-only VPC)
# --------------------------------------------------------------------------------

# module "dns_firewall" {
#   source = "../../modules/dns_firewall"
#
#   project_name  = var.project_name
#   environment   = var.environment
#   vpc_id        = module.network.vpc_id
#   block_domains = []
# }

# --------------------------------------------------------------------------------
# CI/CD (deploy separately - see GitHub issue #2)
# --------------------------------------------------------------------------------

# module "cicd" {
#   source = "../../modules/cicd"
#
#   project_name        = var.project_name
#   environment         = var.environment
#   aws_account_id      = data.aws_caller_identity.current.account_id
#   aws_region          = local.aws_region
#   ecs_cluster_name    = module.app.ecs_cluster_name
#   ecr_repository_urls = module.app.ecr_repository_urls
#   services            = local.services
#   ecs_task_role_arns  = module.app.task_role_arns
#   log_bucket_id       = module.logging.bucket_id
#   kms_key_arn         = module.kms.key_arns["s3"]
# }
