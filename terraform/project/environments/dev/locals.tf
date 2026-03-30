locals {
  aws_region  = "ap-northeast-1"
  vpc_cidr    = var.vpc_cidr
  name_prefix = "${var.project_name}-${var.environment}"

  lanes = {
    user = {
      identifier = "user"
    }
    admin = {
      identifier = "admin"
    }
  }

  azs = ["${local.aws_region}a", "${local.aws_region}c"]

  private_subnets = {
    "${local.aws_region}a" = cidrsubnet(local.vpc_cidr, 8, 11)
    "${local.aws_region}c" = cidrsubnet(local.vpc_cidr, 8, 12)
  }

  security_groups = toset(concat(
    ["ecs", "db", "vpce"],
    [for lane in keys(local.lanes) : "${lane}-alb"]
  ))

  # Interface endpoints for ECS task access to AWS services
  interface_endpoints = {
    ecr-api        = "com.amazonaws.${local.aws_region}.ecr.api"
    ecr-dkr        = "com.amazonaws.${local.aws_region}.ecr.dkr"
    logs           = "com.amazonaws.${local.aws_region}.logs"
    sts            = "com.amazonaws.${local.aws_region}.sts"
    ssm            = "com.amazonaws.${local.aws_region}.ssm"
    secretsmanager = "com.amazonaws.${local.aws_region}.secretsmanager"
  }

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
