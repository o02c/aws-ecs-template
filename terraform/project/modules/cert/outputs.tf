output "regional_certificate_arn" {
  description = "ACM certificate ARN for ALB (regional)"
  value       = aws_acm_certificate_validation.regional.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (us-east-1)"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}
