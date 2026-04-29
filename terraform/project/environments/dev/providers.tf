provider "aws" {
  default_tags {
    tags = {
      ProjectName = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
