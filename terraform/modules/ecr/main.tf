data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── ECR Repositories ─────────────────────────────────────────────────────────
# One repository per service. Using a map allows us to create all repos
# with a single resource block rather than one per service.

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  # Naming convention: prefix/service (e.g. cloudnative-commerce/product-api)
  # This groups repos visually in the AWS console and allows IAM policies
  # to grant access to all repos under a prefix with a single statement.
  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    # Basic scanning: checks OS packages against the CVE database on push.
    # Enhanced scanning (with Amazon Inspector) can be enabled at the registry
    # level for continuous scanning of all images, not just on push.
    scan_on_push = var.scan_on_push
  }

  # Encrypt images at rest using AWS-managed KMS key.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}/${each.key}"
    Service = each.key
  })
}

# ─── Lifecycle Policies ───────────────────────────────────────────────────────
# Without lifecycle policies, ECR storage grows unboundedly.
# Each Docker push creates a new image layer set — over hundreds of builds
# this becomes expensive (ECR storage is $0.10/GB/month).
#
# Two rules per repo:
#   1. Keep only the last N tagged images (configurable per repo)
#   2. Delete untagged images older than 7 days (leftover build layers)

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: expire old tagged images
        # Lower priority number = evaluated first.
        rulePriority = 1
        description  = "Keep last ${coalesce(each.value.image_count_to_keep, var.image_count_to_keep)} tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPatternList = ["*"]
          countType   = "imageCountMoreThan"
          countNumber = coalesce(each.value.image_count_to_keep, var.image_count_to_keep)
        }
        action = { type = "expire" }
      },
      {
        # Rule 2: delete untagged images quickly
        # Untagged images are intermediate build layers pushed during
        # multi-stage builds or failed/aborted pushes.
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus = "untagged"
          countType = "sinceImagePushed"
          countUnit = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── Registry Policy ──────────────────────────────────────────────────────────
# Cross-account pull policy — allows the EKS node role to pull images.
# Without this, nodes can only pull if they have full ECR permissions
# on the node IAM role (which is overly broad).
#
# Note: EKS nodes use the node IAM role for ECR pulls by default.
# This policy adds an explicit allow for auditability.

resource "aws_ecr_registry_policy" "this" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      }
    ]
  })
}
