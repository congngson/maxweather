terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "maxweather-terraform-state"
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "maxweather-terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = "maxweather"
      managed_by = "terraform"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}
