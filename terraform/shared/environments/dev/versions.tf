terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "o02c-terraform-management-tfstate-654654512164"
    key          = "shared/dev/terraform.tfstate"
    region       = "ap-northeast-1"
    profile      = "terraform"
    use_lockfile = true
    encrypt      = true
  }
}
