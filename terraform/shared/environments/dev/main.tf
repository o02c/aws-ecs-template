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
}

# --------------------------------------------------------------------------------
# Network (Shared VPC with Transit Gateway)
# --------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name      = var.project_name
  environment       = var.environment
  vpc_cidr          = local.vpc_cidr
  public_subnets    = local.public_subnets
  private_subnets   = local.private_subnets
  project_vpc_cidrs   = local.project_vpc_cidrs
  gateway_endpoints   = local.gateway_endpoints
  interface_endpoints = local.interface_endpoints
  kms_key_arn         = module.kms.key_arns["logs"]
}

# --------------------------------------------------------------------------------
# IAM
# --------------------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  users  = local.iam_users
  groups = local.iam_groups
}
