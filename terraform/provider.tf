terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.92.0, < 7.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}

provider "aws" {
  # Configuration options
  profile = "sandbox"
  region = "eu-west-1"
}