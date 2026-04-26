output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "enable_nat_gateway" {
  description = "Whether NAT gateways were created"
  value       = var.enable_nat_gateway
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}
