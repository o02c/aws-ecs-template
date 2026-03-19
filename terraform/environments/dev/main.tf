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
}

# --------------------------------------------------------------------------------
# Storage (per-lane)
# --------------------------------------------------------------------------------

module "storage" {
  source   = "../../modules/storage"
  for_each = local.lanes

  project_name = var.project_name
  environment  = var.environment
  lane         = each.key
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
}

# --------------------------------------------------------------------------------
# DNS / ACM
# --------------------------------------------------------------------------------

module "dns" {
  source = "../../modules/dns"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
}

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
