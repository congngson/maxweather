variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to use"
  default     = 2
}

variable "enable_vpc_endpoints" {
  type        = bool
  description = "Whether to create VPC endpoints for AWS services"
  default     = true
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to create NAT gateways (set false to skip in lab/test environments)"
  default     = true
}
