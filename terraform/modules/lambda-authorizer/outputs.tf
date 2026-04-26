output "lambda_function_arn" {
  description = "ARN of the Lambda authorizer function"
  value       = aws_lambda_function.authorizer.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda authorizer (used by API Gateway)"
  value       = aws_lambda_function.authorizer.invoke_arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB API keys table"
  value       = aws_dynamodb_table.api_keys.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB API keys table"
  value       = aws_dynamodb_table.api_keys.arn
}
