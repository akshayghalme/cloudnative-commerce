# ─── IRSA Helper: trust policy factory ───────────────────────────────────────
# Each IRSA role needs an assume_role_policy that trusts tokens from the
# EKS OIDC provider, scoped to a specific Kubernetes ServiceAccount.
#
# The two conditions are critical:
#   :sub = "system:serviceaccount:<namespace>:<serviceaccount>"
#     → only THIS specific ServiceAccount can assume the role
#   :aud = "sts.amazonaws.com"
#     → token must be for STS (not some other audience)
#
# Without the :sub condition, ANY pod in the cluster could assume the role.

locals {
  # Builds the OIDC sub condition value for a given namespace + SA
  oidc_sub = {
    product_api  = "system:serviceaccount:${var.product_api_namespace}:${var.product_api_service_account}"
    order_worker = "system:serviceaccount:${var.order_worker_namespace}:${var.order_worker_service_account}"
    storefront   = "system:serviceaccount:${var.storefront_namespace}:${var.storefront_service_account}"
  }
}

# ─── product-api IRSA Role ────────────────────────────────────────────────────
# product-api needs:
#   - Secrets Manager: GetSecretValue on the RDS credentials secret
#   - ECR: pull its own image (handled by node role, but explicit is better)
#
# What it does NOT get:
#   - SQS (that's order-worker's domain)
#   - S3 (not needed by this service)
#   - Any other secret

resource "aws_iam_role" "product_api" {
  name = "${var.cluster_name}-product-api-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = local.oidc_sub.product_api
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-product-api-irsa"
    Service = "product-api"
  })
}

resource "aws_iam_role_policy" "product_api" {
  name = "${var.cluster_name}-product-api-policy"
  role = aws_iam_role.product_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRDSSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to the exact RDS secret — not all secrets in the account.
        Resource = var.rds_secret_arn
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        # KMS key used to encrypt the Secrets Manager secret at rest.
        # Without this, GetSecretValue fails even with the secret ARN allowed.
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ─── order-worker IRSA Role ───────────────────────────────────────────────────
# order-worker needs:
#   - SQS: ReceiveMessage, DeleteMessage, ChangeMessageVisibility on orders queue
#   - SQS: SendMessage on DLQ (to forward poison-pill messages)
#   - SQS: GetQueueAttributes (for health checks)
#
# What it does NOT get:
#   - RDS credentials (order-worker talks to product-api, not DB directly)
#   - CreateQueue, DeleteQueue (no infrastructure permissions)

resource "aws_iam_role" "order_worker" {
  name = "${var.cluster_name}-order-worker-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = local.oidc_sub.order_worker
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-order-worker-irsa"
    Service = "order-worker"
  })
}

resource "aws_iam_role_policy" "order_worker" {
  name = "${var.cluster_name}-order-worker-policy"
  role = aws_iam_role.order_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeOrdersQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        Sid    = "SendToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = var.sqs_dlq_arn
      }
    ]
  })
}

# ─── storefront IRSA Role ─────────────────────────────────────────────────────
# The storefront (Next.js) is a frontend — it calls product-api via HTTP,
# doesn't touch AWS services directly. It still gets an IRSA role so:
#   - CloudWatch: PutMetricData for custom frontend metrics (Core Web Vitals)
#   - We follow a consistent pattern across all services
#
# An empty role with no policy is also valid — just means no AWS SDK calls.

resource "aws_iam_role" "storefront" {
  name = "${var.cluster_name}-storefront-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = local.oidc_sub.storefront
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-storefront-irsa"
    Service = "storefront"
  })
}

resource "aws_iam_role_policy" "storefront" {
  name = "${var.cluster_name}-storefront-policy"
  role = aws_iam_role.storefront.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutFrontendMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudNativeCommerce/Storefront"
          }
        }
      }
    ]
  })
}

# ─── Data Sources ─────────────────────────────────────────────────────────────

data "aws_region" "current" {}
