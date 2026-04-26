variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "oidc_provider" {
  type        = string
  description = "OIDC provider URL for EKS IRSA (without https://)"
  default     = ""
}
