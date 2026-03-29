# --------------------------------------------------------------------------------
# CodeBuild Project - Docker Build
# --------------------------------------------------------------------------------

resource "aws_codebuild_project" "build" {
  for_each = var.services

  name         = "${var.project_name}-${var.environment}-${each.key}-build"
  description  = "Build Docker image for ${each.key}"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = var.ecr_repository_urls[each.key]
    }

    environment_variable {
      name  = "SERVICE_NAME"
      value = each.key
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-build"
  }
}

# --------------------------------------------------------------------------------
# CodeBuild Project - ecspresso Deploy
# --------------------------------------------------------------------------------

resource "aws_codebuild_project" "deploy" {
  for_each = var.services

  name         = "${var.project_name}-${var.environment}-${each.key}-deploy"
  description  = "Deploy ${each.key} via ecspresso"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ECS_CLUSTER"
      value = var.ecs_cluster_name
    }

    environment_variable {
      name  = "SERVICE_NAME"
      value = each.key
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-deploy"
  }
}
