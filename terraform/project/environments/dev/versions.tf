terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Prerequisites: S3 state bucket must have versioning enabled (required for use_lockfile).
  backend "s3" {
    bucket       = "o02c-terraform-management-tfstate-654654512164"
    key          = "myapp/dev/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
