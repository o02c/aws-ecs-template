# --------------------------------------------------------------------------------
# Service Domain Mapping
# --------------------------------------------------------------------------------

locals {
  # Map endpoint identifier to the actual DNS domain name for each AWS service
  endpoint_dns_domains = {
    for key, service_name in var.interface_endpoints : key => lookup(
      {
        "ecr.api"          = "api.ecr"
        "ecr.dkr"          = "dkr.ecr"
        "logs"             = "logs"
        "kinesis-firehose"  = "firehose"
        "sts"              = "sts"
        "ssm"              = "ssm"
        "secretsmanager"   = "secretsmanager"
      },
      # Extract service suffix from "com.amazonaws.<region>.<service>"
      join(".", slice(split(".", service_name), 3, length(split(".", service_name)))),
      join(".", slice(split(".", service_name), 3, length(split(".", service_name))))
    )
  }

  # Extract region from service name: "com.amazonaws.<region>.<service>"
  endpoint_region = length(var.interface_endpoints) > 0 ? split(".", values(var.interface_endpoints)[0])[2] : ""

  # Full domain for each endpoint
  endpoint_phz_domains = {
    for key, domain_prefix in local.endpoint_dns_domains : key =>
    "${domain_prefix}.${local.endpoint_region}.amazonaws.com"
  }

  # ECR DKR needs wildcard record
  ecr_dkr_endpoints = {
    for key, _ in var.interface_endpoints : key => key
    if local.endpoint_dns_domains[key] == "dkr.ecr"
  }
}

# --------------------------------------------------------------------------------
# Route53 Private Hosted Zones for Interface Endpoints
# --------------------------------------------------------------------------------

resource "aws_route53_zone" "endpoint" {
  for_each = var.interface_endpoints

  name = local.endpoint_phz_domains[each.key]

  vpc {
    vpc_id = aws_vpc.this.id
  }

  lifecycle {
    ignore_changes = [vpc]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-shared-${each.key}-phz"
  }
}

# --------------------------------------------------------------------------------
# ALIAS Records for Interface Endpoints
# --------------------------------------------------------------------------------

resource "aws_route53_record" "endpoint" {
  for_each = var.interface_endpoints

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = local.endpoint_phz_domains[each.key]
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

# ECR DKR needs wildcard record: *.dkr.ecr.<region>.amazonaws.com
resource "aws_route53_record" "endpoint_dkr_wildcard" {
  for_each = local.ecr_dkr_endpoints

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = "*.${local.endpoint_phz_domains[each.key]}"
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}
