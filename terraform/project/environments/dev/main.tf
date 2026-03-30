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
    bucket  = var.shared_state_bucket
    key     = var.shared_state_key
    region  = local.aws_region
    profile = "terraform"
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
}

# --------------------------------------------------------------------------------
# Network
# --------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = local.vpc_cidr
  private_subnets     = local.private_subnets
  security_groups     = local.security_groups
  interface_endpoints = local.interface_endpoints
  gateway_endpoints   = local.gateway_endpoints
  transit_gateway_id  = local.transit_gateway_id
}

# --------------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------------

module "db" {
  source = "../../modules/db"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  db_security_group_id  = module.network.security_group_ids["db"]
  ecs_security_group_id = module.network.security_group_ids["ecs"]

  master_username = var.db_master_username
  master_password = var.db_master_password
  kms_key_arn     = module.kms.key_arns["rds"]

  deletion_protection = false
  skip_final_snapshot = true
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
  acm_certificate_arn   = module.dns.regional_certificate_arn
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
  db_security_group_id   = module.network.security_group_ids["db"]
  vpce_security_group_id = module.network.security_group_ids["vpce"]
  s3_prefix_list_id      = module.network.s3_prefix_list_id
  db_cluster_arn         = module.db.cluster_arn
  db_resource_id         = module.db.cluster_resource_id
  services               = local.services
  s3_bucket_arns = {
    for lane, mod in module.storage : lane => mod.bucket_arn
  }
  rds_iam_auth_policy_arn = module.db.rds_iam_auth_policy_arn
  s3_access_policy_arns = {
    for lane, mod in module.storage : lane => mod.s3_access_policy_arn
  }
  cloudfront_signing_key_secret_arn = var.cloudfront_signing_key_secret_arn
  logs_kms_key_arn                  = module.kms.key_arns["logs"]
  aws_account_id                    = data.aws_caller_identity.current.account_id
  s3_kms_key_arn                    = module.kms.key_arns["s3"]
}

# --------------------------------------------------------------------------------
# CDN (per-lane)
# --------------------------------------------------------------------------------

module "cdn" {
  source   = "../../modules/cdn"
  for_each = local.lanes

  project_name                   = var.project_name
  environment                    = var.environment
  lane                           = each.key
  alb_dns_name                   = module.lb[each.key].alb_dns_name
  alb_arn                        = module.lb[each.key].alb_arn
  s3_bucket_regional_domain_name = module.storage[each.key].bucket_regional_domain_name
  s3_bucket_id                   = module.storage[each.key].bucket_id
  cloudfront_oac_id              = module.storage[each.key].cloudfront_oac_id
  acm_certificate_arn            = module.dns.cloudfront_certificate_arn
  aliases                        = ["${each.key}.${var.domain_name}"]
  domain_name                    = var.domain_name
  route53_zone_id                = module.dns.zone_id
  enable_signing                 = nonsensitive(var.cloudfront_signing_public_key_pem != "")
  signing_public_key_pem         = var.cloudfront_signing_public_key_pem
  log_bucket_domain_name         = module.logging.bucket_domain_name
  log_prefix                     = "cloudfront/${each.key}/"
  vpc_id                         = module.network.vpc_id
  alb_security_group_id          = module.network.security_group_ids["${each.key}-alb"]
}

# --------------------------------------------------------------------------------
# DNS / ACM
# --------------------------------------------------------------------------------

module "dns" {
  source = "../../modules/dns"

  project_name        = var.project_name
  environment         = var.environment
  domain_name         = var.domain_name
  manage_registrar_ns = true
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
#   ecs_cluster_name    = module.app.ecs_cluster_name
#   ecr_repository_urls = module.app.ecr_repository_urls
#   services            = local.services
#   ecs_task_role_arns  = module.app.task_role_arns
# }
