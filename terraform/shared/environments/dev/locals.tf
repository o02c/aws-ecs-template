locals {
  aws_region = "ap-northeast-1"
  vpc_cidr   = "10.0.0.0/16"

  azs = ["${local.aws_region}a", "${local.aws_region}c"]

  public_subnets = {
    "${local.aws_region}a" = cidrsubnet(local.vpc_cidr, 8, 1)
    "${local.aws_region}c" = cidrsubnet(local.vpc_cidr, 8, 2)
  }

  private_subnets = {
    "${local.aws_region}a" = cidrsubnet(local.vpc_cidr, 8, 11)
    "${local.aws_region}c" = cidrsubnet(local.vpc_cidr, 8, 12)
  }

  gateway_endpoints = {
    s3 = "com.amazonaws.${local.aws_region}.s3"
  }

  # Project VPC CIDRs for TGW return routes
  # Add entries here as new projects are created
  project_vpc_cidrs = {
    myapp = "10.1.0.0/16"
  }

  # IAM Users
  iam_users = {
    # "admin-user" = {
    #   groups = ["administrators"]
    # }
  }

  # IAM Groups
  iam_groups = {
    # administrators = {
    #   policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    # }
  }
}
