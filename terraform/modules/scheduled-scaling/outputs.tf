output "scheduled_action_names" {
  description = "List of created ASG scheduled action names"
  value       = [for k, v in aws_autoscaling_schedule.this : v.scheduled_action_name]
}
