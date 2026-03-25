# Dev environment — wires all modules together.
# Each module is added as tasks are completed.
# Current: VPC + EKS + RDS + ElastiCache + ECR + IAM/IRSA.

locals {
  name   = "${var.project}-${var.environment}"
  region = var.aws_region

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = "10.0.0.0/16"
  az_count             = 3
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # Dev cost optimization: single NAT GW (~$32/month vs ~$96/month for 3).
  # See ADR-001 for the trade-off analysis.
  single_nat_gateway = true

  cluster_name            = local.name
  flow_log_retention_days = 30

  tags = local.tags
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.name
  cluster_version = "1.30"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # t3.medium: 2 vCPU, 4GB RAM — enough for 3 small services + system pods in dev.
  # In prod, upgrade to m5.large or m5.xlarge for headroom.
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 3
  node_disk_size_gb   = 50

  # API server accessible from the internet (dev: developer laptops need kubectl).
  # Lock down public_access_cidrs to your IP in prod, or disable public access entirely.
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  tags = local.tags
}

# ─── RDS ──────────────────────────────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_cidr_block     = module.vpc.vpc_cidr_block

  # Only EKS nodes can reach the database.
  allowed_security_group_ids = [module.eks.node_security_group_id]

  engine_version           = "16.3"
  instance_class           = "db.t3.micro" # ~$13/month in dev
  allocated_storage_gb     = 20
  max_allocated_storage_gb = 100

  database_name     = "commerce"
  database_username = "commerce_admin"

  # Dev: no Multi-AZ (saves ~$13/month), 7-day backups, no deletion protection.
  multi_az              = false
  backup_retention_days = 7
  deletion_protection   = false
  skip_final_snapshot   = true

  tags = local.tags
}

# ─── ElastiCache (Redis) ───────────────────────────────────────────────────────

module "elasticache" {
  source = "../../modules/elasticache"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Only EKS nodes can reach Redis.
  allowed_security_group_ids = [module.eks.node_security_group_id]

  engine_version  = "7.1"
  node_type       = "cache.t3.micro" # ~$12/month in dev
  num_cache_nodes = 1

  # Dev: encryption at rest, no TLS in transit (simplifies local debugging).
  # In prod: set transit_encryption_enabled = true and provide auth_token.
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  snapshot_retention_limit = 1

  tags = local.tags
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  name_prefix          = local.name
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting a tag once pushed
  scan_on_push         = true
  image_count_to_keep  = 20

  repositories = {
    product-api  = {}
    storefront   = {}
    order-worker = {}
  }

  tags = local.tags
}

# ─── IAM / IRSA ───────────────────────────────────────────────────────────────

module "iam" {
  source = "../../modules/iam"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # product-api: reads RDS credentials from Secrets Manager
  rds_secret_arn = module.rds.db_secret_arn

  # order-worker: SQS ARNs populated once queue is created (Task 27 CI)
  # Using wildcard for now — tightened when SQS module is added
  sqs_queue_arn = "arn:aws:sqs:${var.aws_region}:*:${local.name}-orders"
  sqs_dlq_arn   = "arn:aws:sqs:${var.aws_region}:*:${local.name}-orders-dlq"

  tags = local.tags
}
