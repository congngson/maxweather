# ── ASG Scheduled Actions (Node-level pre-warm) ───────────────────────────────
# All times in UTC. WIB = UTC+7.
# Architecture defines 5 schedule windows matching the scaling timeline:
#
#   06:00 WIB  Weekday pre-warm  → 23:00 UTC previous day (Mon-Fri)
#   07:30 WIB  Weekend warm      → 00:30 UTC (Sat-Sun)
#   10:30 WIB  Post-peak down    → 03:30 UTC (Mon-Fri and Sat-Sun)
#   22:00 WIB  Night mode        → 15:00 UTC daily

locals {
  schedule_config = {
    weekday-prewarm = {
      recurrence    = "0 23 * * 0-4"   # 06:00 WIB Mon-Fri (fires Sun-Thu UTC)
      min_size      = var.schedule_weekday_peak.min_size
      max_size      = var.schedule_weekday_peak.max_size
      desired_count = var.schedule_weekday_peak.desired_count
    }
    weekday-postpeak = {
      recurrence    = "30 3 * * 1-5"   # 10:30 WIB Mon-Fri
      min_size      = var.schedule_weekday_offpeak.min_size
      max_size      = var.schedule_weekday_offpeak.max_size
      desired_count = var.schedule_weekday_offpeak.desired_count
    }
    weekend-warm = {
      recurrence    = "30 0 * * 6,0"   # 07:30 WIB Sat-Sun
      min_size      = var.schedule_weekend_peak.min_size
      max_size      = var.schedule_weekend_peak.max_size
      desired_count = var.schedule_weekend_peak.desired_count
    }
    weekend-postpeak = {
      recurrence    = "30 3 * * 6,0"   # 10:30 WIB Sat-Sun
      min_size      = var.schedule_weekend_offpeak.min_size
      max_size      = var.schedule_weekend_offpeak.max_size
      desired_count = var.schedule_weekend_offpeak.desired_count
    }
    night-mode = {
      recurrence    = "0 15 * * *"     # 22:00 WIB daily
      min_size      = var.schedule_night.min_size
      max_size      = var.schedule_night.max_size
      desired_count = var.schedule_night.desired_count
    }
  }
}

resource "aws_autoscaling_schedule" "this" {
  for_each = {
    for combo in flatten([
      for ng_name, ng_asg in var.node_group_asg_names : [
        for action_name, action_cfg in local.schedule_config : {
          key           = "${ng_name}-${action_name}"
          asg_name      = ng_asg
          recurrence    = action_cfg.recurrence
          min_size      = action_cfg.min_size
          max_size      = action_cfg.max_size
          desired_count = action_cfg.desired_count
        }
      ]
    ]) : combo.key => combo
  }

  scheduled_action_name  = each.key
  autoscaling_group_name = each.value.asg_name
  recurrence             = each.value.recurrence
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_count
}
