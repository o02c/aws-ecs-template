# --------------------------------------------------------------------------------
# Route53 Hosted Zone
# --------------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.domain_name}"
  }
}

# --------------------------------------------------------------------------------
# Domain Registrar Nameserver Sync
# --------------------------------------------------------------------------------
# Always enabled: this template assumes the root domain is registered with
# Route53 Domains (AWS-registered) so the NS records of the registrar must
# match the hosted zone. If a future project hosts the registrar elsewhere,
# restore a feature flag then.

resource "aws_route53domains_registered_domain" "this" {
  domain_name = var.domain_name

  dynamic "name_server" {
    for_each = aws_route53_zone.this.name_servers
    content {
      name = name_server.value
    }
  }
}
