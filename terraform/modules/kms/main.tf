data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  services   = ["aurora", "elasticache", "eks", "s3"]
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

data "aws_iam_policy_document" "kms" {
  for_each = toset(local.services)

  # Root account full access (required)
  statement {
    sid     = "RootAccess"
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow CloudWatch Logs to use the key for log group encryption
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    }
  }

  # Allow SNS to use the key
  statement {
    sid    = "AllowSNS"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "this" {
  for_each = toset(local.services)

  description             = "MaxWeather ${var.environment} — ${each.key}"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[each.key].json

  tags = {
    environment = var.environment
    service     = each.key
  }
}

resource "aws_kms_alias" "this" {
  for_each = toset(local.services)

  name          = "alias/maxweather-${var.environment}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}
