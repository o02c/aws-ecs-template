# --------------------------------------------------------------------------------
# ECR Repositories
# --------------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = var.services

  name                 = "${var.project_name}-${var.environment}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}

# --------------------------------------------------------------------------------
# Lifecycle Policy
# --------------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.services

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# nginx ECR Repository (shared across services)
# --------------------------------------------------------------------------------

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project_name}-${var.environment}-nginx"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nginx"
  }
}

# --------------------------------------------------------------------------------
# Fluent Bit ECR Repository (mirror of init-latest from public.ecr.aws)
# --------------------------------------------------------------------------------

resource "aws_ecr_repository" "fluent_bit" {
  name                 = "${var.project_name}-${var.environment}-fluent-bit"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  }
}

# --------------------------------------------------------------------------------
# Pull-through Cache (public.ecr.aws -> private ECR)
# --------------------------------------------------------------------------------
# Fargate private subnets can't reach public.ecr.aws directly.
# Pull-through cache auto-mirrors public images on first pull.
# ref: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
#
# Image URI format:
#   <account>.dkr.ecr.<region>.amazonaws.com/ecr-public/<namespace>/<repo>:<tag>
#
# Auto-created cache repos must be deleted separately (not managed by Terraform).
# See justfile ecr-delete-cache recipe.

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

