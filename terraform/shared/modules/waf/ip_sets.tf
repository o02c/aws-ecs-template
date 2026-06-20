# --------------------------------------------------------------------------------
# Per-rule IP sets (CLOUDFRONT scope -> us-east-1, IPv4)
# --------------------------------------------------------------------------------
# Allowlist semantics under default-block: each allow rule passes traffic whose
# source IP IS in this set. One set per allow rule.
#
# WAFv2 IP sets reject 0.0.0.0/0, so an "open" allowlist is expressed as the two
# halves that together cover all IPv4. Operators can still write ["0.0.0.0/0"].

resource "aws_wafv2_ip_set" "this" {
  for_each = local.rules
  region   = "us-east-1"

  name               = "${var.name_prefix}-${local.rule_name[each.key]}"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = flatten([for c in each.value.cidrs : c == "0.0.0.0/0" ? ["0.0.0.0/1", "128.0.0.0/1"] : [c]])

  tags = {
    Name = "${var.name_prefix}-${local.rule_name[each.key]}"
  }
}
