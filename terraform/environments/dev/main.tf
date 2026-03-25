# Dev environment — wires all modules together.
# Each module is added as tasks are completed.
# Current: VPC + EKS. RDS, ElastiCache added in Tasks 12–13.

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
