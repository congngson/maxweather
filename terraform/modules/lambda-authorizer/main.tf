data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/authorizer.zip"
}

# ── DynamoDB API Key Store ────────────────────────────────────────────────────

resource "aws_dynamodb_table" "api_keys" {
  name         = "maxweather-${var.environment}-api-keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "api_key"

  attribute {
    name = "api_key"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { environment = var.environment }
}

# ── Lambda Function ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/maxweather/${var.environment}/lambda/authorizer"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { environment = var.environment }
}

resource "aws_lambda_function" "authorizer" {
  function_name = "maxweather-${var.environment}-authorizer"
  description   = "API Gateway Lambda authorizer for MaxWeather ${var.environment}"

  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  handler          = "authorizer.handler"
  runtime          = "python3.12"

  role        = var.lambda_role_arn
  timeout     = 5
  memory_size = 128

  environment {
    variables = {
      API_KEYS_TABLE = aws_dynamodb_table.api_keys.name
    }
  }

  kms_key_arn = var.kms_key_arn

  depends_on = [aws_cloudwatch_log_group.authorizer]

  tags = { environment = var.environment }
}
