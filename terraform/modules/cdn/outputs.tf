output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "signing_key_pair_id" {
  description = "CloudFront signing key pair ID for signed URL generation"
  value       = try(aws_cloudfront_public_key.signing["default"].id, "")
}

output "signing_key_group_id" {
  description = "CloudFront signing key group ID"
  value       = try(aws_cloudfront_key_group.signing["default"].id, "")
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.this.arn
}
