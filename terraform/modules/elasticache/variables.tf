variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for encryption at rest"
}

variable "node_type" {
  type        = string
  description = "ElastiCache node type"
  default     = "cache.r7g.large"
}

variable "num_cache_clusters" {
  type        = number
  description = "Number of cache clusters (1 = single-node, 2+ = Multi-AZ)"
  default     = 2
}

variable "preferred_azs" {
  type        = list(string)
  description = "Preferred AZs for cache clusters (must match num_cache_clusters length)"
  default     = []
}

variable "slow_log_group_name" {
  type        = string
  description = "CloudWatch log group name for Valkey slow logs"
}

variable "engine_log_group_name" {
  type        = string
  description = "CloudWatch log group name for Valkey engine logs"
}
