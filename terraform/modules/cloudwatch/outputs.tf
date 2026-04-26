output "log_group_names" {
  description = "Map of log group key to CloudWatch log group name"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "alerts_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "valkey_slow_log_group_name" {
  description = "CloudWatch log group name for Valkey slow logs"
  value       = aws_cloudwatch_log_group.this["valkey_slow"].name
}

output "valkey_engine_log_group_name" {
  description = "CloudWatch log group name for Valkey engine logs"
  value       = aws_cloudwatch_log_group.this["valkey_engine"].name
}
