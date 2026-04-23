locals {
  aws_region = "ap-northeast-1"
  vpc_cidr   = "10.0.0.0/16"

  # VPC flow log CloudWatch retention (days). Dev keeps short, prod should be longer.
  flow_log_retention_days = 30

  # KMS keys managed at the shared state layer. Used by shared-owned resources
  # (shared VPC flow log encryption など). project 側の同名 key とは state 境界が
  # 違うため別物（terraform-conventions skill §8 参照）。
  kms_keys = {
    general = {
      description = "CMK for shared infrastructure encryption"
      service     = null
    }
    logs = {
      description = "CMK for CloudWatch Logs encryption"
      service     = "logs.${local.aws_region}.amazonaws.com"
    }
  }

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

  # Interface endpoints shared across all project VPCs.
  # wildcard = true creates a *.<dns> alias (ECR DKR needs this for image pulls).
  interface_endpoints = {
    ecr-api        = { service = "com.amazonaws.${local.aws_region}.ecr.api", wildcard = false }
    ecr-dkr        = { service = "com.amazonaws.${local.aws_region}.ecr.dkr", wildcard = true }
    logs           = { service = "com.amazonaws.${local.aws_region}.logs", wildcard = false }
    firehose       = { service = "com.amazonaws.${local.aws_region}.kinesis-firehose", wildcard = false }
    sts            = { service = "com.amazonaws.${local.aws_region}.sts", wildcard = false }
    ssm            = { service = "com.amazonaws.${local.aws_region}.ssm", wildcard = false }
    secretsmanager = { service = "com.amazonaws.${local.aws_region}.secretsmanager", wildcard = false }
  }

  # Project VPC CIDRs for TGW return routes
  # Add entries here as new projects are created
  project_vpc_cidrs = {
    myapp = "10.1.0.0/16"
  }

  # IAM Users — all auto-enrolled in the mfa-enforced group.
  # Additional group names must match aws_iam_group resources defined in
  # terraform/shared/modules/iam/iam_group_<name>.tf.
  iam_users = {
    # "alice" = {
    #   groups = ["developer"]
    # }
  }
}
