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

# ── Weather Lambda ────────────────────────────────────────────────────────────
resource "aws_iam_role" "weather" {
  name = "maxweather-${local.env}-weather"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "weather_basic" {
  role       = aws_iam_role.weather.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "weather" {
  type        = "zip"
  source_file = "${path.module}/src/weather.py"
  output_path = "${path.module}/.build/weather.zip"
}

resource "aws_lambda_function" "weather" {
  function_name    = "maxweather-${local.env}-weather"
  role             = aws_iam_role.weather.arn
  filename         = data.archive_file.weather.output_path
  source_code_hash = data.archive_file.weather.output_base64sha256
  runtime          = "python3.12"
  handler          = "weather.handler"
  timeout          = 10

  environment {
    variables = {
      OWM_API_KEY = "1251a6ad5d43460195bc162ffdd44250"
    }
  }
}

# ── API Gateway (REST API — compatible with Lambda Authorizer IAM policy format)
resource "aws_api_gateway_rest_api" "main" {
  name = "maxweather-${local.env}"
}

# IAM role for API Gateway to invoke Lambda functions
resource "aws_iam_role" "apigw_invoker" {
  name = "maxweather-${local.env}-apigw-invoker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "apigw_invoker" {
  name = "invoke-lambdas"
  role = aws_iam_role.apigw_invoker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [
        module.lambda_authorizer.lambda_function_arn,
        aws_lambda_function.weather.arn
      ]
    }]
  })
}

# Lambda Authorizer
resource "aws_api_gateway_authorizer" "lambda" {
  name                             = "maxweather-${local.env}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  authorizer_uri                   = module.lambda_authorizer.lambda_invoke_arn
  authorizer_credentials           = aws_iam_role.apigw_invoker.arn
  identity_source                  = "method.request.header.Authorization"
  type                             = "REQUEST"
  authorizer_result_ttl_in_seconds = 300
}

# GET /health — no auth
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "health" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.health.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.weather.invoke_arn
}

# ANY /{proxy+} — requires auth
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.weather.invoke_arn
}

# Allow API Gateway to invoke Lambda functions
resource "aws_lambda_permission" "apigw_weather" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "maxweather-${local.env}-authorizer"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Deploy
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.health,
    aws_api_gateway_integration.proxy,
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.health.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.health.id,
      aws_api_gateway_method.proxy.id,
    ]))
  }
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = local.env
}

# ── DynamoDB: seed test API key ───────────────────────────────────────────────
resource "aws_dynamodb_table_item" "test_key" {
  table_name = module.lambda_authorizer.dynamodb_table_name
  hash_key   = "api_key"

  item = jsonencode({
    api_key = { S = "demo-key-maxweather-2026" }
    active  = { BOOL = true }
    client  = { S = "demo-client" }
  })

  depends_on = [module.lambda_authorizer]
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

output "api_endpoint" {
  value = "${aws_api_gateway_stage.main.invoke_url}"
}

output "demo_api_key" {
  value = "demo-key-maxweather-2026"
}
