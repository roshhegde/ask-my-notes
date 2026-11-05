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

# `terraform workspace select local` points everything at Floci (a free AWS
# emulator on your Mac) instead of real AWS. The default workspace is real AWS.
# Each workspace keeps its own state, so the two never touch each other.
locals {
  use_floci  = terraform.workspace == "local"
  floci_url  = "http://localhost:4566"
  ollama_url = "http://host.docker.internal:11434" # Ollama on your Mac, as seen from Docker
}

provider "aws" {
  region = var.region

  access_key                  = local.use_floci ? "test" : null
  secret_key                  = local.use_floci ? "test" : null
  skip_credentials_validation = local.use_floci
  skip_requesting_account_id  = local.use_floci
  skip_metadata_api_check     = local.use_floci
  s3_use_path_style           = local.use_floci

  dynamic "endpoints" {
    for_each = local.use_floci ? [1] : []
    content {
      apigatewayv2 = local.floci_url
      budgets      = local.floci_url
      iam          = local.floci_url
      lambda       = local.floci_url
      logs         = local.floci_url
      s3           = local.floci_url
      sts          = local.floci_url
    }
  }

  default_tags {
    tags = {
      Project = var.project_name
      Owner   = "roshhegde"
    }
  }
}
