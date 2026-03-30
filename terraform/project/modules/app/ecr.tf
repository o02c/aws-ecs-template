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

# --------------------------------------------------------------------------------
# Fluent Bit ECR Repository (shared across services)
# --------------------------------------------------------------------------------

resource "aws_ecr_repository" "fluent_bit" {
  name                 = "${var.project_name}-${var.environment}-fluent-bit"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-fluent-bit"
  }
}

resource "aws_ecr_lifecycle_policy" "fluent_bit" {
  repository = aws_ecr_repository.fluent_bit.name

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
