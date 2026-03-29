# --------------------------------------------------------------------------------
# Route 53 Resolver DNS Firewall
# --------------------------------------------------------------------------------

resource "aws_route53_resolver_firewall_domain_list" "block" {
  name    = "${var.project_name}-${var.environment}-block"
  domains = var.block_domains

  tags = {
    Name = "${var.project_name}-${var.environment}-block"
  }
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  name = "${var.project_name}-${var.environment}"

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_route53_resolver_firewall_rule" "block" {
  name                    = "block-malicious-domains"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.block.id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  priority                = 100
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  name                   = "${var.project_name}-${var.environment}"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this.id
  vpc_id                 = var.vpc_id
  priority               = 101

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
