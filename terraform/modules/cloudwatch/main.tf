# ── Log Groups ────────────────────────────────────────────────────────────────

locals {
  log_groups = {
    app           = "/maxweather/${var.environment}/app"
    eks           = "/maxweather/${var.environment}/eks"
    aurora        = "/maxweather/${var.environment}/aurora"
    valkey_slow   = "/maxweather/${var.environment}/valkey/slow-log"
    valkey_engine = "/maxweather/${var.environment}/valkey/engine-log"
    api_gateway   = "/maxweather/${var.environment}/api-gateway"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { environment = var.environment }
}

# ── SNS Topic for Alerts ──────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name              = "maxweather-${var.environment}-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = { environment = var.environment }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "maxweather-${var.environment}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora CPU utilization exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  tags = { environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "maxweather-${var.environment}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 400
  alarm_description   = "Aurora connection count exceeds 400"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  tags = { environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "valkey_cpu" {
  alarm_name          = "maxweather-${var.environment}-valkey-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Valkey engine CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ReplicationGroupId = var.valkey_replication_group_id
  }

  tags = { environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "valkey_memory" {
  alarm_name          = "maxweather-${var.environment}-valkey-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Valkey memory usage exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ReplicationGroupId = var.valkey_replication_group_id
  }

  tags = { environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "maxweather-${var.environment}-api-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway 5XX errors exceed 10 in 1 minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = "MaxWeather-${var.environment}"
  }

  tags = { environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "maxweather-${var.environment}-api-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2000
  alarm_description   = "API Gateway p99 latency exceeds 2 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = "MaxWeather-${var.environment}"
  }

  tags = { environment = var.environment }
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "MaxWeather-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "API Gateway — Requests & Errors"
          region  = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", "MaxWeather-${var.environment}", { stat = "Sum", label = "Requests" }],
            ["AWS/ApiGateway", "5XXError", "ApiName", "MaxWeather-${var.environment}", { stat = "Sum", label = "5XX Errors", color = "#d62728" }],
            ["AWS/ApiGateway", "4XXError", "ApiName", "MaxWeather-${var.environment}", { stat = "Sum", label = "4XX Errors", color = "#ff7f0e" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "API Gateway — Latency (p50 / p99)"
          region  = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "IntegrationLatency", "ApiName", "MaxWeather-${var.environment}", { stat = "p50", label = "p50" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiName", "MaxWeather-${var.environment}", { stat = "p99", label = "p99", color = "#d62728" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Aurora — CPU & Connections"
          region  = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${var.aurora_cluster_identifier}", { stat = "Average", label = "CPU %" }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "${var.aurora_cluster_identifier}", { stat = "Average", label = "Connections", yAxis = "right" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Valkey — CPU & Memory"
          region  = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "EngineCPUUtilization", "ReplicationGroupId", "${var.valkey_replication_group_id}", { stat = "Average", label = "CPU %" }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", "${var.valkey_replication_group_id}", { stat = "Average", label = "Memory %", yAxis = "right" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
    ]
  })
}
