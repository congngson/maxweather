variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for ECR image encryption"
}
