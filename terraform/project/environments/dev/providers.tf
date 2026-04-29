provider "aws" {
  default_tags {
    tags = {
      ProjectName = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      ProjectName = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
