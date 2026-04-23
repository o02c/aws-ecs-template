# --------------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------------

# Use the actually-created endpoints (not the input var) as the for_each basis.
# If endpoints are ever filtered/disabled, data sources follow automatically.
# For some services (e.g. ECR DKR) private_dns_name has a leading "*." which
# Route53 zones don't allow — strip it for the zone and add a wildcard record.
data "aws_vpc_endpoint_service" "interface" {
  for_each = aws_vpc_endpoint.interface

  service_name = each.value.service_name
}

locals {
  endpoint_zone_names = {
    for key in keys(aws_vpc_endpoint.interface) : key =>
    trimprefix(data.aws_vpc_endpoint_service.interface[key].private_dns_name, "*.")
  }

  # Wildcard filter comes from var (plan-time known) so downstream for_each
  # on this local doesn't depend on apply-time data.
  wildcard_endpoints = {
    for key, cfg in var.interface_endpoints : key => true
    if cfg.wildcard
  }
}

# --------------------------------------------------------------------------------
# Route53 Private Hosted Zones for Interface Endpoints
# --------------------------------------------------------------------------------

resource "aws_route53_zone" "endpoint" {
  for_each = aws_vpc_endpoint.interface

  name = local.endpoint_zone_names[each.key]

  vpc {
    vpc_id = aws_vpc.this.id
  }

  lifecycle {
    ignore_changes = [vpc]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Alias Records for Interface Endpoints
# --------------------------------------------------------------------------------

resource "aws_route53_record" "endpoint" {
  for_each = aws_vpc_endpoint.interface

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = local.endpoint_zone_names[each.key]
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

# Wildcard record for services that advertise their private DNS with "*." prefix
# (e.g. ECR DKR serves images from *.dkr.ecr.<region>.amazonaws.com).
resource "aws_route53_record" "endpoint_wildcard" {
  for_each = local.wildcard_endpoints

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = "*.${local.endpoint_zone_names[each.key]}"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
