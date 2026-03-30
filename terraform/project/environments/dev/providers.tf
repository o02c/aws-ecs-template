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

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "terraform"

  default_tags {
    tags = {
      ProjectName = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
