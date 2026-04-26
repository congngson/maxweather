resource "aws_security_group" "cluster" {
  name        = "maxweather-${var.environment}-eks-cluster"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "maxweather-${var.environment}-eks-cluster-sg"
    environment = var.environment
  }
}

resource "aws_eks_cluster" "this" {
  name     = "maxweather-${var.environment}"
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_server_allowed_cidrs
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  tags = { environment = var.environment }

  depends_on = [var.cluster_role_arn]
}

# OIDC provider for IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = { environment = var.environment }
}

# ── Node Groups ───────────────────────────────────────────────────────────────

resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix = "maxweather-${var.environment}-${each.key}-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "maxweather-${var.environment}-${each.key}"
      environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  tags = {
    environment = var.environment
    "k8s.io/cluster-autoscaler/enabled"                          = "true"
    "k8s.io/cluster-autoscaler/maxweather-${var.environment}"   = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ── EKS Add-ons ───────────────────────────────────────────────────────────────

resource "aws_eks_addon" "addons" {
  for_each = {
    vpc-cni            = { version = null, resolve_conflicts = "OVERWRITE" }
    coredns            = { version = null, resolve_conflicts = "OVERWRITE" }
    kube-proxy         = { version = null, resolve_conflicts = "OVERWRITE" }
    aws-ebs-csi-driver = { version = null, resolve_conflicts = "OVERWRITE" }
  }

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.key
  addon_version            = each.value.version
  resolve_conflicts_on_update = each.value.resolve_conflicts

  tags = { environment = var.environment }
}
