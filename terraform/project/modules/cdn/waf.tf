# --------------------------------------------------------------------------------
# IP Allowlist (optional)
# --------------------------------------------------------------------------------
# Two scopes only: "admin" gates the single non-default lane's path prefix;
# "global" gates every request. Empty allowed_cidrs disables the rule.
# This template intentionally assumes exactly one non-default lane to keep the
# WAF rule shape constant; `one()` errors if that assumption is broken.

locals {
  ip_allowlist_enabled = length(var.ip_allowlist.allowed_cidrs) > 0
  admin_path_prefix    = one([for _, v in var.lanes : v.path_prefix if v.path_prefix != ""])
}

resource "aws_wafv2_ip_set" "allow" {
  # Always created (count = 1) even when allowed_cidrs is empty. Letting terraform
  # destroy the IPSet while the WACL still references it triggers an unrecoverable
  # WAFAssociatedItemException because terraform updates WACL and destroys IPSet
  # in parallel. Keeping the IPSet permanent and gating only the rule sidesteps
  # the ordering issue entirely. An empty IPSet is harmless (and free).
  count  = 1
  region = "us-east-1"

  name               = "${var.project_name}-${var.environment}-allow"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist.allowed_cidrs

  tags = {
    Name = "${var.project_name}-${var.environment}-allow"
  }
}

# --------------------------------------------------------------------------------
# WAFv2 Web ACL (must be in us-east-1 for CloudFront)
# --------------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  region = "us-east-1"

  name  = "${var.project_name}-${var.environment}"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # --------------------------------------------------------------------------------
  # IP Allowlist rule (priority 1; before managed rules)
  # --------------------------------------------------------------------------------
  # scope=admin:  block when URI starts_with admin_path_prefix AND IP NOT in allowlist
  # scope=global: block when IP NOT in allowlist (any path)
  dynamic "rule" {
    for_each = local.ip_allowlist_enabled ? { (var.ip_allowlist.scope) = true } : {}

    content {
      name     = "ip-allowlist-${rule.key}"
      priority = 1

      action {
        block {}
      }

      statement {
        # scope=admin: AND(starts_with admin prefix, NOT in allowlist).
        dynamic "and_statement" {
          for_each = rule.key == "admin" ? [1] : []
          content {
            statement {
              byte_match_statement {
                search_string         = local.admin_path_prefix
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
            statement {
              not_statement {
                statement {
                  ip_set_reference_statement {
                    arn = aws_wafv2_ip_set.allow[0].arn
                  }
                }
              }
            }
          }
        }

        # scope=global: NOT in allowlist (no path filter).
        dynamic "not_statement" {
          for_each = rule.key == "global" ? [1] : []
          content {
            statement {
              ip_set_reference_statement {
                arn = aws_wafv2_ip_set.allow[0].arn
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-${var.environment}-allow-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  # --------------------------------------------------------------------------------
  # AWS Managed Rules - Common Rule Set
  # --------------------------------------------------------------------------------
  rule {
    name     = "aws-managed-common"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-common"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------------
  # AWS Managed Rules - SQL Injection Rule Set
  # --------------------------------------------------------------------------------
  rule {
    name     = "aws-managed-sqli"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------------
  # AWS Managed Rules - Known Bad Inputs Rule Set
  # --------------------------------------------------------------------------------
  rule {
    name     = "aws-managed-bad-inputs"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------------
  # Rate-based Rule
  # --------------------------------------------------------------------------------
  rule {
    name     = "rate-limit"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
