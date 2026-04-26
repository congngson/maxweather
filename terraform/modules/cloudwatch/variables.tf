variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "aws_region" {
  type        = string
  description = "AWS region (used in dashboard widget properties)"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for log group encryption"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention period in days"
  default     = 30
}

variable "alert_email" {
  type        = string
  description = "Email address to receive SNS alert notifications (empty to skip)"
  default     = ""
}

variable "aurora_cluster_identifier" {
  type        = string
  description = "Aurora cluster identifier for alarm dimensions"
}

variable "valkey_replication_group_id" {
  type        = string
  description = "ElastiCache Valkey replication group ID for alarm dimensions"
}
