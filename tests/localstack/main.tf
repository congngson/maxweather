terraform {
  required_version = ">= 1.7.0"
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
}

provider "aws" {
  region                      = "ap-southeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    kms            = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    s3             = "http://localhost:4566"
    iam            = "http://localhost:4566"
    logs           = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sts            = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
  }
}

locals {
  env = "localtest"
}

# ── KMS ───────────────────────────────────────────────────────────────────────
module "kms" {
  source      = "../../terraform/modules/kms"
  environment = local.env
}

# ── CloudWatch ────────────────────────────────────────────────────────────────
module "cloudwatch" {
  source      = "../../terraform/modules/cloudwatch"
  environment = local.env
  kms_key_arn = module.kms.key_arns["eks"]

  log_retention_days          = 7
  alert_email                 = ""
  aurora_cluster_identifier   = "maxweather-${local.env}"
  valkey_replication_group_id = "maxweather-${local.env}"
}

# ── Lambda Authorizer ─────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "maxweather-${local.env}-lambda-authorizer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

module "lambda_authorizer" {
  source          = "../../terraform/modules/lambda-authorizer"
  environment     = local.env
  aws_region      = "ap-southeast-1"
  lambda_role_arn = aws_iam_role.lambda.arn
  kms_key_arn     = module.kms.key_arns["eks"]
  log_retention_days = 7
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "kms_key_ids" {
  value = module.kms.key_ids
}

output "log_groups" {
  value = module.cloudwatch.log_group_names
}

output "sns_topic_arn" {
  value = module.cloudwatch.alerts_topic_arn
}

output "lambda_arn" {
  value = module.lambda_authorizer.lambda_function_arn
}

output "dynamodb_table" {
  value = module.lambda_authorizer.dynamodb_table_name
}
