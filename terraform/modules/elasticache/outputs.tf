output "primary_endpoint" {
  description = "Primary endpoint address of the Valkey replication group"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address of the Valkey replication group"
  value       = aws_elasticache_replication_group.valkey.reader_endpoint_address
}

output "port" {
  description = "Port for the Valkey replication group"
  value       = aws_elasticache_replication_group.valkey.port
}

output "security_group_id" {
  description = "ID of the Valkey security group"
  value       = aws_security_group.valkey.id
}
