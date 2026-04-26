data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ── EKS Cluster Role ──────────────────────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "maxweather-${var.environment}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Node Group Role ───────────────────────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "maxweather-${var.environment}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])

  role       = aws_iam_role.eks_node.name
  policy_arn = each.key
}

# ── IRSA: Cluster Autoscaler ──────────────────────────────────────────────────
resource "aws_iam_role" "cluster_autoscaler" {
  name = "maxweather-${var.environment}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "maxweather-${var.environment}-cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"                            = "true"
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/maxweather-${var.environment}" = "owned"
          }
        }
      },
    ]
  })
}

# ── IRSA: AWS Load Balancer Controller ───────────────────────────────────────
resource "aws_iam_role" "aws_lb_controller" {
  name = "maxweather-${var.environment}-aws-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy" "aws_lb_controller" {
  name   = "maxweather-${var.environment}-aws-lb-controller"
  role   = aws_iam_role.aws_lb_controller.id
  policy = file("${path.module}/policies/aws-lb-controller.json")
}

# ── IRSA: Fluent Bit (log shipping) ──────────────────────────────────────────
resource "aws_iam_role" "fluent_bit" {
  name = "maxweather-${var.environment}-fluent-bit"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${var.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:logging:fluent-bit"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy" "fluent_bit" {
  name = "maxweather-${var.environment}-fluent-bit"
  role = aws_iam_role.fluent_bit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = "arn:aws:logs:*:${local.account_id}:log-group:/maxweather/${var.environment}/*"
    }]
  })
}

# ── Jenkins CI Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "jenkins" {
  name = "maxweather-${var.environment}-jenkins"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy" "jenkins" {
  name = "maxweather-${var.environment}-jenkins"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:*:${local.account_id}:cluster/maxweather-${var.environment}"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "maxweather-${var.environment}-jenkins"
  role = aws_iam_role.jenkins.name
}

# ── Lambda Authorizer Role ────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_authorizer" {
  name = "maxweather-${var.environment}-lambda-authorizer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "lambda_authorizer_basic" {
  role       = aws_iam_role.lambda_authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_authorizer_dynamodb" {
  name = "maxweather-${var.environment}-lambda-authorizer-ddb"
  role = aws_iam_role.lambda_authorizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = "arn:aws:dynamodb:*:${local.account_id}:table/maxweather-${var.environment}-api-keys"
    }]
  })
}
