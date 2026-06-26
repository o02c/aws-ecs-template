# --------------------------------------------------------------------------------
# CloudFront KeyValueStore: maintenance gate
# --------------------------------------------------------------------------------
# Holds a single key `maintenance` ("on" | "off") read by the viewer-request
# function (cloudfront_function.tf) to serve a 503 page on the frontend behaviors.
#
# The key's VALUE is written at runtime by the maintenance module
# (DescribeKeyValueStore -> PutKey via Lambda; the data-plane API requires SigV4A,
# so Terraform never owns the value). The store starts empty; the function fails
# open (no key / error -> normal routing), so "off" needs no seeding.

resource "aws_cloudfront_key_value_store" "maintenance" {
  name    = "${var.project_name}-${var.environment}-maintenance"
  comment = "Maintenance flag read by the ${var.project_name}-${var.environment} viewer-request function"
}
