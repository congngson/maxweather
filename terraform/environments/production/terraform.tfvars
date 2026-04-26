aws_region             = "ap-southeast-1"
vpc_cidr               = "10.0.0.0/16"
az_count               = 3
kubernetes_version     = "1.34"
alert_email            = ""
aurora_instance_class  = "db.r7g.large"
valkey_node_type       = "cache.r7g.large"
valkey_num_clusters    = 2
eks_reserved_instance_type = "m7i.xlarge"
eks_reserved_min       = 3
eks_reserved_max       = 6
eks_reserved_desired   = 3
eks_burst_instance_type = "m7i.large"
eks_burst_min          = 0
eks_burst_max          = 7
eks_burst_desired      = 0
log_retention_days     = 90

schedule_weekday_peak    = { min_size = 6, max_size = 10, desired_count = 6 }
schedule_weekday_offpeak = { min_size = 3, max_size = 7, desired_count = 3 }
schedule_weekend_peak    = { min_size = 4, max_size = 8, desired_count = 4 }
schedule_weekend_offpeak = { min_size = 3, max_size = 7, desired_count = 3 }
schedule_night           = { min_size = 2, max_size = 4, desired_count = 2 }
