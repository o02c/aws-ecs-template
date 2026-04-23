# --------------------------------------------------------------------------------
# WAF (base, no IP restriction)
# --------------------------------------------------------------------------------

module "waf_base" {
  source   = "../../modules/waf_base"
  for_each = local.lanes_base

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  lane         = each.key
}

# --------------------------------------------------------------------------------
# WAF (IP-restricted)
# --------------------------------------------------------------------------------

module "waf_ip_restricted" {
  source   = "../../modules/waf_ip_restricted"
  for_each = local.lanes_ip_restricted

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  lane         = each.key
  ip_allowlist = each.value.ip_allowlist
}

# 他モジュールへ渡す web_acl_arn は両方を merge する
locals {
  web_acl_arns = merge(
    { for k, m in module.waf_base : k => m.web_acl_arn },
    { for k, m in module.waf_ip_restricted : k => m.web_acl_arn },
  )
}
