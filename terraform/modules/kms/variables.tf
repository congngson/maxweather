variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "deletion_window_in_days" {
  type        = number
  description = "KMS key deletion window in days"
  default     = 7
}
