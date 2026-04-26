resource "aws_db_subnet_group" "this" {
  name        = "maxweather-${var.environment}"
  description = "MaxWeather ${var.environment} Aurora subnet group"
  subnet_ids  = var.subnet_ids

  tags = { environment = var.environment }
}

resource "aws_security_group" "aurora" {
  name        = "maxweather-${var.environment}-aurora"
  description = "Allow PostgreSQL from within VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "maxweather-${var.environment}-aurora-sg"
    environment = var.environment
  }
}

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "maxweather/${var.environment}/aurora/master"
  description             = "Aurora master credentials for MaxWeather ${var.environment}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = { environment = var.environment }
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id
  secret_string = jsonencode({
    username = "maxweather_admin"
    password = random_password.master.result
    host     = aws_rds_cluster.this.endpoint
    port     = 5432
    dbname   = "maxweather"
  })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "maxweather-${var.environment}-aurora-pg16"
  family      = "aurora-postgresql16"
  description = "MaxWeather ${var.environment} Aurora PostgreSQL 16 parameters"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = { environment = var.environment }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = "maxweather-${var.environment}"
  engine                  = "aurora-postgresql"
  engine_version          = "16.4"
  database_name           = "maxweather"
  master_username         = "maxweather_admin"
  master_password         = random_password.master.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period   = var.environment == "production" ? 14 : 7
  preferred_backup_window   = "17:00-18:00"
  preferred_maintenance_window = "sun:18:00-sun:19:00"

  deletion_protection      = var.environment == "production"
  skip_final_snapshot      = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "maxweather-production-final-${formatdate("YYYYMMDD", timestamp())}" : null

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { environment = var.environment }

  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier           = "maxweather-${var.environment}-writer"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.this.name

  availability_zone          = var.writer_az
  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.environment == "production" ? 731 : 7

  tags = {
    environment = var.environment
    role        = "writer"
  }
}

resource "aws_rds_cluster_instance" "reader" {
  count = var.create_reader ? 1 : 0

  identifier           = "maxweather-${var.environment}-reader"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.this.name

  availability_zone          = var.reader_az
  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.environment == "production" ? 731 : 7

  tags = {
    environment = var.environment
    role        = "reader"
  }
}

# Enhanced Monitoring Role (shared, created once per account — use data source if pre-existing)
resource "aws_iam_role" "enhanced_monitoring" {
  name = "maxweather-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
