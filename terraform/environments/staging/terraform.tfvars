aws_region             = "ap-southeast-1"
vpc_cidr               = "10.1.0.0/16"
az_count               = 2
kubernetes_version     = "1.34"
alert_email            = ""
aurora_instance_class  = "db.t4g.medium"
valkey_node_type       = "cache.t4g.medium"
valkey_num_clusters    = 1
eks_node_instance_type = "m7i.large"
eks_node_min           = 1
eks_node_max           = 4
eks_node_desired       = 2
log_retention_days     = 14

schedule_weekday_peak    = { min_size = 2, max_size = 4, desired_count = 3 }
schedule_weekday_offpeak = { min_size = 1, max_size = 4, desired_count = 2 }
schedule_weekend_peak    = { min_size = 2, max_size = 4, desired_count = 2 }
schedule_weekend_offpeak = { min_size = 1, max_size = 4, desired_count = 1 }
schedule_night           = { min_size = 1, max_size = 4, desired_count = 1 }
