provider "aws" {
  region  = local.aws_region
  profile = "terraform"

  default_tags {
    tags = {
      ProjectName = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
