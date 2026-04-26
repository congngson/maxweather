output "cluster_endpoint" {
  description = "Writer endpoint of the Aurora cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the Aurora cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding master credentials"
  value       = aws_secretsmanager_secret.aurora_master.arn
}

output "security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}
