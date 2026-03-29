# --------------------------------------------------------------------------------
# WAFv2 Web ACL (must be in us-east-1 for CloudFront)
# --------------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  region = "us-east-1"

  name  = "${var.project_name}-${var.environment}-${var.lane}"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # --------------------------------------------------------------------------
  # AWS Managed Rules - Common Rule Set
  # --------------------------------------------------------------------------
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
      metric_name                = "${var.project_name}-${var.environment}-${var.lane}-common"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------
  # AWS Managed Rules - SQL Injection Rule Set
  # --------------------------------------------------------------------------
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
      metric_name                = "${var.project_name}-${var.environment}-${var.lane}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------
  # AWS Managed Rules - Known Bad Inputs Rule Set
  # --------------------------------------------------------------------------
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
      metric_name                = "${var.project_name}-${var.environment}-${var.lane}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # --------------------------------------------------------------------------
  # Rate-based Rule
  # --------------------------------------------------------------------------
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
      metric_name                = "${var.project_name}-${var.environment}-${var.lane}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-${var.lane}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}
