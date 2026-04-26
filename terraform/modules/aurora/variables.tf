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
  description = "VPC CIDR block (used for ingress rule)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the DB subnet group"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for encryption at rest"
}

variable "instance_class" {
  type        = string
  description = "Aurora instance class"
  default     = "db.r7g.large"
}

variable "writer_az" {
  type        = string
  description = "Availability zone for the writer instance"
}

variable "reader_az" {
  type        = string
  description = "Availability zone for the reader instance"
  default     = ""
}

variable "create_reader" {
  type        = bool
  description = "Whether to create a reader instance (set false for staging)"
  default     = true
}
