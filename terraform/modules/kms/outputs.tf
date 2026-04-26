output "key_arns" {
  description = "Map of service name to KMS key ARN"
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}

output "key_ids" {
  description = "Map of service name to KMS key ID"
  value       = { for k, v in aws_kms_key.this : k => v.key_id }
}
