data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]

  vpc_endpoint_services = ["ecr.api", "ecr.dkr", "s3", "logs", "monitoring", "dynamodb"]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "maxweather-${var.environment}"
    environment = var.environment
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "maxweather-${var.environment}-igw"
    environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "maxweather-${var.environment}-public-${local.azs[count.index]}"
    environment              = var.environment
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "maxweather-${var.environment}-private-${local.azs[count.index]}"
    environment                       = var.environment
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? var.az_count : 0
  domain = "vpc"

  tags = {
    Name        = "maxweather-${var.environment}-nat-eip-${count.index}"
    environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? var.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "maxweather-${var.environment}-nat-${local.azs[count.index]}"
    environment = var.environment
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "maxweather-${var.environment}-public-rt"
    environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[count.index].id
    }
  }

  tags = {
    Name        = "maxweather-${var.environment}-private-rt-${local.azs[count.index]}"
    environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "maxweather-${var.environment}-vpc-endpoints"
  description = "Allow HTTPS from within VPC to AWS service endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "maxweather-${var.environment}-vpc-endpoints-sg"
    environment = var.environment
  }
}

resource "aws_vpc_endpoint" "this" {
  for_each = toset(var.enable_vpc_endpoints ? local.vpc_endpoint_services : [])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = each.key == "s3" || each.key == "dynamodb" ? "Gateway" : "Interface"
  subnet_ids          = each.key == "s3" || each.key == "dynamodb" ? null : aws_subnet.private[*].id
  security_group_ids  = each.key == "s3" || each.key == "dynamodb" ? null : [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = each.key == "s3" || each.key == "dynamodb" ? false : true

  tags = {
    Name        = "maxweather-${var.environment}-endpoint-${each.key}"
    environment = var.environment
  }
}
