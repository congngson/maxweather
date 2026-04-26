variable "environment" {
  type        = string
  description = "Environment name (staging | production)"
}

variable "node_group_asg_names" {
  type        = map(string)
  description = "Map of node group name to ASG name pattern (from EKS node group resources)"
}

variable "schedule_weekday_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  description = "ASG config for weekday pre-warm (06:00 UTC+7 Mon-Fri = 23:00 UTC Sun-Thu)"
}

variable "schedule_weekday_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  description = "ASG config for weekday post-peak (10:30 UTC+7 Mon-Fri = 03:30 UTC Mon-Fri)"
}

variable "schedule_weekend_peak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  description = "ASG config for weekend warm (07:30 UTC+7 Sat-Sun = 00:30 UTC Sat-Sun)"
}

variable "schedule_weekend_offpeak" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  description = "ASG config for weekend post-peak (10:30 UTC+7 Sat-Sun = 03:30 UTC Sat-Sun)"
}

variable "schedule_night" {
  type = object({
    min_size      = number
    max_size      = number
    desired_count = number
  })
  description = "ASG config for night mode (22:00 UTC+7 daily = 15:00 UTC daily)"
}
