terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }

  backend "s3" {
    bucket         = "maxweather-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "maxweather-terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "maxweather"
      environment = "staging"
      managed_by  = "terraform"
    }
  }
}

locals {
  env = "staging"
}

module "kms" {
  source      = "../../modules/kms"
  environment = local.env
}

module "vpc" {
  source               = "../../modules/vpc"
  environment          = local.env
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  enable_vpc_endpoints = true
}

module "iam" {
  source        = "../../modules/iam"
  environment   = local.env
  oidc_provider = module.eks.oidc_provider_url
}

module "ecr" {
  source      = "../../modules/ecr"
  environment = local.env
  kms_key_arn = module.kms.key_arns["s3"]
}

module "cloudwatch" {
  source      = "../../modules/cloudwatch"
  environment = local.env
  aws_region  = var.aws_region
  kms_key_arn = module.kms.key_arns["eks"]

  log_retention_days          = var.log_retention_days
  alert_email                 = var.alert_email
  aurora_cluster_identifier   = module.aurora.cluster_identifier
  valkey_replication_group_id = "maxweather-${local.env}"
}

module "aurora" {
  source         = "../../modules/aurora"
  environment    = local.env
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  kms_key_arn    = module.kms.key_arns["aurora"]
  instance_class = var.aurora_instance_class
  writer_az      = "${var.aws_region}a"
  reader_az      = "${var.aws_region}b"
  create_reader  = false
}

module "elasticache" {
  source                = "../../modules/elasticache"
  environment           = local.env
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  subnet_ids            = module.vpc.private_subnet_ids
  kms_key_arn           = module.kms.key_arns["elasticache"]
  node_type             = var.valkey_node_type
  num_cache_clusters    = var.valkey_num_clusters
  slow_log_group_name   = module.cloudwatch.valkey_slow_log_group_name
  engine_log_group_name = module.cloudwatch.valkey_engine_log_group_name
}

module "eks" {
  source             = "../../modules/eks"
  environment        = local.env
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  cluster_role_arn   = module.iam.eks_cluster_role_arn
  node_role_arn      = module.iam.eks_node_role_arn
  kms_key_arn        = module.kms.key_arns["eks"]
  kubernetes_version = var.kubernetes_version

  node_groups = {
    ondemand = {
      instance_types = [var.eks_node_instance_type]
      capacity_type  = "ON_DEMAND"
      desired_size   = var.eks_node_desired
      min_size       = var.eks_node_min
      max_size       = var.eks_node_max
      labels         = { role = "app", env = local.env }
    }
  }
}

module "lambda_authorizer" {
  source             = "../../modules/lambda-authorizer"
  environment        = local.env
  lambda_role_arn    = module.iam.lambda_authorizer_role_arn
  kms_key_arn        = module.kms.key_arns["eks"]
  log_retention_days = var.log_retention_days
}

module "scheduled_scaling" {
  source      = "../../modules/scheduled-scaling"
  environment = local.env

  node_group_asg_names = {
    for k, v in module.eks.node_group_names : k =>
    "eks-${module.eks.cluster_name}-${v}-*"
  }

  schedule_weekday_peak    = var.schedule_weekday_peak
  schedule_weekday_offpeak = var.schedule_weekday_offpeak
  schedule_weekend_peak    = var.schedule_weekend_peak
  schedule_weekend_offpeak = var.schedule_weekend_offpeak
  schedule_night           = var.schedule_night
}
