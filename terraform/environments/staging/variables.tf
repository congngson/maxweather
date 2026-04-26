variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
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
  default = "db.t4g.medium"
}

variable "valkey_node_type" {
  type    = string
  default = "cache.t4g.medium"
}

variable "valkey_num_clusters" {
  type    = number
  default = 1
}

variable "eks_node_instance_type" {
  type    = string
  default = "m7i.large"
}

variable "eks_node_min" {
  type    = number
  default = 1
}

variable "eks_node_max" {
  type    = number
  default = 4
}

variable "eks_node_desired" {
  type    = number
  default = 2
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "schedule_weekday_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 2, max_size = 4, desired_count = 3 }
}

variable "schedule_weekday_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 1, max_size = 4, desired_count = 2 }
}

variable "schedule_weekend_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 2, max_size = 4, desired_count = 2 }
}

variable "schedule_weekend_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 1, max_size = 4, desired_count = 1 }
}

variable "schedule_night" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  default = { min_size = 1, max_size = 4, desired_count = 1 }
}
