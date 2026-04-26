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
  # local backend — no S3 needed for lab testing
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      project     = "maxweather"
      environment = "awslab"
      managed_by  = "terraform"
    }
  }
}

locals {
  env = "awslab"
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
  aws_region  = "us-east-1"
  kms_key_arn = module.kms.key_arns["eks"]

  log_retention_days          = 1
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

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "maxweather-awslab-lambda-ddb"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.current.account_id}:table/maxweather-awslab-api-keys"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = module.kms.key_arns["eks"]
      }
    ]
  })
}

module "lambda_authorizer" {
  source             = "../../terraform/modules/lambda-authorizer"
  environment        = local.env
  lambda_role_arn    = aws_iam_role.lambda.arn
  kms_key_arn        = module.kms.key_arns["eks"]
  log_retention_days = 1
}

# ── VPC (lightweight: no NAT GW to save cost) ────────────────────────────────
module "vpc" {
  source               = "../../terraform/modules/vpc"
  environment          = local.env
  aws_region           = "us-east-1"
  vpc_cidr             = "10.99.0.0/16"
  az_count             = 2
  enable_nat_gateway   = false
  enable_vpc_endpoints = false
}

# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  source      = "../../terraform/modules/ecr"
  environment = local.env
  kms_key_arn = module.kms.key_arns["s3"]
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "account_id" {
  value = "961341524524"
}

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

output "lambda_invoke_arn" {
  value = module.lambda_authorizer.lambda_invoke_arn
}

output "dynamodb_table" {
  value = module.lambda_authorizer.dynamodb_table_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}
