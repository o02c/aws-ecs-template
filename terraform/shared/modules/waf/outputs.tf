output "web_acl_arn" {
  description = "ARN of the shared CLOUDFRONT Web ACL (for reference; association is owned by FMS)."
  value       = aws_wafv2_web_acl.fms.arn
}

output "web_acl_id" {
  description = "ID of the shared CLOUDFRONT Web ACL."
  value       = aws_wafv2_web_acl.fms.id
}

output "ip_set_arns" {
  description = "Per-rule IP set ARNs, keyed \"<domain>#base\" or \"<domain>#path:<path>\"."
  value       = { for k, v in aws_wafv2_ip_set.this : k => v.arn }
}
