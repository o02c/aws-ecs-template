# --------------------------------------------------------------------------------
# IP Set
# --------------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "allowlist" {
  provider           = aws.us_east_1
  name               = "${var.project_name}-${var.environment}-${var.lane}-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist
}

# --------------------------------------------------------------------------------
# Web ACL (common rules + IP allowlist)
# --------------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "${var.project_name}-${var.environment}-${var.lane}"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

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

  rule {
    name     = "IPAllowlist"
    priority = 100
    action {
      block {}
    }
    statement {
      not_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.allowlist.arn
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

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-${var.lane}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}
