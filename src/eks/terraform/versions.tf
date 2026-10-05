terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }

  # State local (src/eks/terraform/terraform.tfstate, ignorado no git). Para um POC
  # descartável de uma pessoa só é suficiente; se mais gente for aplicar,
  # migrar para um backend S3.
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      project    = "poc-argo-rollouts"
      managed-by = "terraform"
    }
  }
}
