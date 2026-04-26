resource "aws_elasticache_subnet_group" "this" {
  name        = "maxweather-${var.environment}"
  description = "MaxWeather ${var.environment} ElastiCache subnet group"
  subnet_ids  = var.subnet_ids

  tags = { environment = var.environment }
}

resource "aws_security_group" "valkey" {
  name        = "maxweather-${var.environment}-valkey"
  description = "Allow Valkey from within VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "maxweather-${var.environment}-valkey-sg"
    environment = var.environment
  }
}

resource "aws_elasticache_parameter_group" "valkey" {
  name        = "maxweather-${var.environment}-valkey8"
  family      = "valkey8"
  description = "MaxWeather ${var.environment} Valkey 8 parameters"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = { environment = var.environment }
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "maxweather-${var.environment}"
  description          = "MaxWeather ${var.environment} Valkey cluster"

  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  parameter_group_name = aws_elasticache_parameter_group.valkey.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.valkey.id]

  port = 6379

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn

  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  preferred_cache_cluster_azs = var.preferred_azs

  snapshot_retention_limit = var.environment == "production" ? 7 : 1
  snapshot_window          = "16:00-17:00"
  maintenance_window       = "sun:17:00-sun:18:00"

  auto_minor_version_upgrade = true

  log_delivery_configuration {
    destination      = var.slow_log_group_name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = var.engine_log_group_name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = { environment = var.environment }
}
