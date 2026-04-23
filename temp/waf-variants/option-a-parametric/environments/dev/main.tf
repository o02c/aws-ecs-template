# --------------------------------------------------------------------------------
# WAF (per-lane, parametric)
# --------------------------------------------------------------------------------

module "waf" {
  source   = "../../modules/waf"
  for_each = local.lanes

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  lane         = each.key
  ip_allowlist = each.value.ip_allowlist
}
