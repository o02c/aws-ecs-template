# --------------------------------------------------------------------------------
# CloudFront Distribution
# --------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name}-${var.environment}-${var.lane}"
  price_class     = "PriceClass_200"

  # ALB origin (VPC origin)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # S3 origin
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = var.cloudfront_oac_id
  }

  # Default behavior (API → ALB)
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb"
    cache_policy_id        = aws_cloudfront_cache_policy.api.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Static assets behavior (S3)
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3"
    cache_policy_id        = aws_cloudfront_cache_policy.static.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.lane}"
  }
}

# --------------------------------------------------------------------------------
# S3 Bucket Policy for CloudFront OAC
# --------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "cloudfront_oac" {
  bucket = var.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.s3_bucket_id}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}
