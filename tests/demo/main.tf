terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = "maxweather", environment = "demo", managed_by = "terraform" }
  }
}

locals { env = "demo" }

# ── DynamoDB — API key store ──────────────────────────────────────────────────
resource "aws_dynamodb_table" "api_keys" {
  name         = "maxweather-${local.env}-api-keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "api_key"

  attribute {
    name = "api_key"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "demo_key" {
  table_name = aws_dynamodb_table.api_keys.name
  hash_key   = "api_key"
  item = jsonencode({
    api_key = { S = var.demo_api_key }
    active  = { BOOL = true }
    client  = { S = "demo-client" }
  })
}

# ── IAM — Lambda Authorizer ───────────────────────────────────────────────────
resource "aws_iam_role" "authorizer" {
  name = "maxweather-${local.env}-authorizer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "authorizer_basic" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "authorizer_ddb" {
  name = "ddb-read"
  role = aws_iam_role.authorizer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.api_keys.arn
    }]
  })
}

# ── Lambda — Authorizer ───────────────────────────────────────────────────────
data "archive_file" "authorizer" {
  type        = "zip"
  source_file = "${path.module}/src/authorizer.py"
  output_path = "${path.module}/.build/authorizer.zip"
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "maxweather-${local.env}-authorizer"
  role             = aws_iam_role.authorizer.arn
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  runtime          = "python3.12"
  handler          = "authorizer.handler"
  timeout          = 5

  environment {
    variables = {
      API_KEYS_TABLE = aws_dynamodb_table.api_keys.name
    }
  }
}

# ── IAM — Weather Lambda ──────────────────────────────────────────────────────
resource "aws_iam_role" "weather" {
  name = "maxweather-${local.env}-weather"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "weather_basic" {
  role       = aws_iam_role.weather.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Lambda — Weather proxy ────────────────────────────────────────────────────
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
    variables = { OWM_API_KEY = var.owm_api_key }
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "main" {
  name = "maxweather-${local.env}"
}

resource "aws_iam_role" "apigw_invoker" {
  name = "maxweather-${local.env}-apigw-invoker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "apigateway.amazonaws.com" }, Action = "sts:AssumeRole" }]
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
      Resource = [aws_lambda_function.authorizer.arn, aws_lambda_function.weather.arn]
    }]
  })
}

resource "aws_api_gateway_authorizer" "lambda" {
  name                             = "maxweather-${local.env}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
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
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_integration.health, aws_api_gateway_integration.proxy]
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

# ── Outputs ───────────────────────────────────────────────────────────────────
output "api_endpoint" { value = aws_api_gateway_stage.main.invoke_url }
output "demo_api_key" { value = "demo-key-maxweather-2026" }
