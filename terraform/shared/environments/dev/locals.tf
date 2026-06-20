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
    email          = { service = "com.amazonaws.${local.aws_region}.email", wildcard = false }
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

  # --------------------------------------------------------------------------------
  # WAF — account-wide CLOUDFRONT Web ACL (per-domain IP allowlist, default-block)
  # --------------------------------------------------------------------------------
  # default_action is block, so EVERY served domain must be registered below or it
  # is fully blocked; an open domain must allow ["0.0.0.0/0"].
  # dev (this account, no Firewall Manager): Terraform creates the ACL and the
  # project distribution associates it (module.cdn web_acl_arn reads the output) —
  # WAF is explicitly present even though dev leaves the domain open.
  # prod: point web_acl_name at the FMS-deployed ACL and `terraform import` it
  # (FMS owns association); see modules/waf.
  waf = {
    enabled      = true
    web_acl_name = "shared-dev-cloudfront" # dev: fresh Terraform-created ACL name
    domains = {
      # dev domain left open; managed rules still apply. Narrow to restrict.
      "oo2cc.click" = { allowed_cidrs = ["0.0.0.0/0"] }
    }
  }
}
