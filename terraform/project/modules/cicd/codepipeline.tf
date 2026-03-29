# --------------------------------------------------------------------------------
# CodePipeline
# --------------------------------------------------------------------------------

resource "aws_codepipeline" "this" {
  for_each = var.services

  name          = "${var.project_name}-${var.environment}-${each.key}"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifact.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "S3Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket             = aws_s3_bucket.artifact.bucket
        S3ObjectKey          = "${each.key}/source.zip"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "DockerBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.build[each.key].name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "EcspressoDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy[each.key].name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  }
}