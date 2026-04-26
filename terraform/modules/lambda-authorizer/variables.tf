variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "lambda_role_arn" {
  type        = string
  description = "IAM role ARN for the Lambda authorizer"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for DynamoDB and Lambda encryption"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 30
}
