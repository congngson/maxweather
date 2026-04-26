variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for node groups"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs (included in cluster VPC config for ALB)"
}

variable "cluster_role_arn" {
  type        = string
  description = "IAM role ARN for the EKS cluster"
}

variable "node_role_arn" {
  type        = string
  description = "IAM role ARN for EKS node groups"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for EKS secrets encryption and EBS volumes"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.34"
}

variable "api_server_allowed_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API server endpoint"
  default     = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = map(string)
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
}
