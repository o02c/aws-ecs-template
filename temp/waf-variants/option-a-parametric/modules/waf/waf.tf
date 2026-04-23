# --------------------------------------------------------------------------------
# IP Allowlist (only when ip_allowlist is non-empty)
# --------------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "allowlist" {
  for_each = length(var.ip_allowlist) > 0 ? { enabled = true } : {}

  provider           = aws.us_east_1
  name               = "${var.project_name}-${var.environment}-${var.lane}-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist
}

# --------------------------------------------------------------------------------
# Web ACL
# --------------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "${var.project_name}-${var.environment}-${var.lane}"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Common managed rule: AWS Managed Common Rule Set
  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 1
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
      metric_name                = "${var.project_name}-${var.environment}-${var.lane}-common"
      sampled_requests_enabled   = true
    }
  }

  # Optional: IP allowlist. Only instantiated when ip_allowlist is non-empty.
  dynamic "rule" {
    for_each = length(var.ip_allowlist) > 0 ? { enabled = true } : {}
    content {
      name     = "IPAllowlist"
      priority = 100
      action {
        block {}
      }
      statement {
        not_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.allowlist["enabled"].arn
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-${var.environment}-${var.lane}-ip-allowlist"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-${var.lane}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}
