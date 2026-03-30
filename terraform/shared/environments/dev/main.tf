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
}

# --------------------------------------------------------------------------------
# Network (Shared VPC with NAT Gateway + Transit Gateway)
# --------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_name      = var.project_name
  environment       = var.environment
  vpc_cidr          = local.vpc_cidr
  public_subnets    = local.public_subnets
  private_subnets   = local.private_subnets
  enable_nat        = false
  enable_ha_nat     = false
  project_vpc_cidrs = local.project_vpc_cidrs
  gateway_endpoints = local.gateway_endpoints
}

# --------------------------------------------------------------------------------
# IAM
# --------------------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  users  = local.iam_users
  groups = local.iam_groups
}
