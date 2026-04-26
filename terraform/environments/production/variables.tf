variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "aurora_instance_class" {
  type    = string
  default = "db.r7g.large"
}

variable "valkey_node_type" {
  type    = string
  default = "cache.r7g.large"
}

variable "valkey_num_clusters" {
  type    = number
  default = 2
}

variable "eks_reserved_instance_type" {
  type    = string
  default = "m7i.xlarge"
}

variable "eks_reserved_min" {
  type    = number
  default = 3
}

variable "eks_reserved_max" {
  type    = number
  default = 6
}

variable "eks_reserved_desired" {
  type    = number
  default = 3
}

variable "eks_burst_instance_type" {
  type    = string
  default = "m7i.large"
}

variable "eks_burst_min" {
  type    = number
  default = 0
}

variable "eks_burst_max" {
  type    = number
  default = 7
}

variable "eks_burst_desired" {
  type    = number
  default = 0
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "schedule_weekday_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 6, max_size = 10, desired_count = 6 }
}

variable "schedule_weekday_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 3, max_size = 7, desired_count = 3 }
}

variable "schedule_weekend_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 4, max_size = 8, desired_count = 4 }
}

variable "schedule_weekend_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 3, max_size = 7, desired_count = 3 }
}

variable "schedule_night" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 2, max_size = 4, desired_count = 2 }
}
