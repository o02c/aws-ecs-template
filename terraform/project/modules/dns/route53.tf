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

resource "aws_route53domains_registered_domain" "this" {
  for_each = var.manage_registrar_ns ? { "main" = true } : {}

  domain_name = var.domain_name

  dynamic "name_server" {
    for_each = aws_route53_zone.this.name_servers
    content {
      name = name_server.value
    }
  }
}
