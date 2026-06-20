# --------------------------------------------------------------------------------
# FMS-deployed CLOUDFRONT Web ACL (imported, managed here) — default-block
# --------------------------------------------------------------------------------
# This ACL is created by Firewall Manager and shared across every CloudFront in the
# account. We own the rule authoring section; FMS enforces its default block outside
# this definition (not a visible rule), so nothing extra is re-declared here.
#
# default_action is BLOCK: every request not matched by an allow rule below is
# blocked. A Host absent from var.domains is therefore fully blocked.
#
# IMPORT (one-time):
#   terraform import 'module.waf.aws_wafv2_web_acl.fms' <NAME>/<ID>/CLOUDFRONT
# (CLOUDFRONT-scope ACLs import against us-east-1; the resource sets region below.)

resource "aws_wafv2_web_acl" "fms" {
  region = "us-east-1"

  name  = var.web_acl_name
  scope = "CLOUDFRONT"

  default_action {
    block {}
  }

  # --------------------------------------------------------------------------------
  # Per-domain allow rules (priority 100+; Host-keyed)
  # --------------------------------------------------------------------------------
  # base       : AND(Host == domain, IP in allowlist, NOT starts_with <each carved path>)
  # path rule  : AND(Host == domain, uri starts_with path, IP in allowlist)
  # Host is matched EXACTLY after LOWERCASE normalization. (Caveat: a Host header
  # carrying an explicit port would not match EXACTLY — CloudFront viewer requests
  # normally omit it; switch to ENDS_WITH if it bites.)
  dynamic "rule" {
    for_each = local.rules

    content {
      name     = "ipallow-${local.rule_name[rule.key]}"
      priority = local.rule_priority[rule.key]

      action {
        allow {}
      }

      statement {
        and_statement {
          # Host == domain
          statement {
            byte_match_statement {
              search_string         = rule.value.domain
              positional_constraint = "EXACTLY"
              field_to_match {
                single_header {
                  name = "host"
                }
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }

          # uri starts_with path (path rules only)
          # NOTE: STARTS_WITH is a raw string prefix, not a path-segment match
          # ("/api" also matches "/apixyz"). Over-blocks only, never over-permits.
          # A regex match (e.g. "^/api(/|$)") would be the proper fix; see locals.tf.
          dynamic "statement" {
            for_each = rule.value.path != "" ? [1] : []
            content {
              byte_match_statement {
                search_string         = rule.value.path
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }

          # carve path_rules paths out of the base rule (NOT starts_with <path>)
          dynamic "statement" {
            for_each = toset(rule.value.excl)
            content {
              not_statement {
                statement {
                  byte_match_statement {
                    search_string         = statement.value
                    positional_constraint = "STARTS_WITH"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }

          # source IP in allowlist
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.this[rule.key].arn
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "ipallow-${local.rule_name[rule.key]}"
        sampled_requests_enabled   = true
      }
    }
  }

  # --------------------------------------------------------------------------------
  # AWS managed rule groups (priority 10-30, before the allow rules)
  # --------------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.managed_rules_enabled ? local.managed_rule_groups : {}

    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # --------------------------------------------------------------------------------
  # Rate-based rule (priority 40)
  # --------------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.managed_rules_enabled ? { "rate-limit" = true } : {}

    content {
      name     = "rate-limit"
      priority = 40

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.web_acl_name
    sampled_requests_enabled   = true
  }

  lifecycle {
    # FMS owns the ACL name; ignore so it never drifts back.
    ignore_changes = [name]
  }
}
