# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

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
# Network (Shared VPC with Transit Gateway)
# --------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name            = var.project_name
  environment             = var.environment
  aws_account_id          = data.aws_caller_identity.current.account_id
  vpc_cidr                = local.vpc_cidr
  public_subnets          = local.public_subnets
  private_subnets         = local.private_subnets
  project_vpc_cidrs       = local.project_vpc_cidrs
  gateway_endpoints       = local.gateway_endpoints
  interface_endpoints     = local.interface_endpoints
  kms_key_arn             = module.kms.key_arns["logs"]
  flow_log_retention_days = local.flow_log_retention_days
}

# --------------------------------------------------------------------------------
# IAM
# --------------------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
  users        = local.iam_users
}

# --------------------------------------------------------------------------------
# WAF (account-wide CLOUDFRONT Web ACL: per-domain IP allowlist, default-block)
# --------------------------------------------------------------------------------
# Single Web ACL shared across every CloudFront in the account. In prod it is the
# Firewall-Manager-deployed ACL (import it, see modules/waf/web_acl.tf); FMS owns
# the association. Disabled in dev (no FMS); enable per-env via local.waf.enabled
# once the domain allowlist and (prod) the imported ACL name are set.

module "waf" {
  source   = "../../modules/waf"
  for_each = local.waf.enabled ? { this = true } : {}

  name_prefix  = "${var.project_name}-${var.environment}"
  web_acl_name = local.waf.web_acl_name
  domains      = local.waf.domains
}
