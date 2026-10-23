terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # State is kept locally on purpose: an S3 + DynamoDB state backend is
  # cheap but adds setup we don't need for a solo learning project.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.project_name
      Owner   = "roshhegde"
    }
  }
}
