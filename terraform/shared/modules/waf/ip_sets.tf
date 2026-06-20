# --------------------------------------------------------------------------------
# Per-rule IP sets (CLOUDFRONT scope -> us-east-1, IPv4)
# --------------------------------------------------------------------------------
# Allowlist semantics under default-block: each allow rule passes traffic whose
# source IP IS in this set. One set per allow rule.

resource "aws_wafv2_ip_set" "this" {
  for_each = local.rules
  region   = "us-east-1"

  name               = "${var.name_prefix}-${local.rule_name[each.key]}"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = each.value.cidrs

  tags = {
    Name = "${var.name_prefix}-${local.rule_name[each.key]}"
  }
}
