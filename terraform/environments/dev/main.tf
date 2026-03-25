# Dev environment — wires all modules together.
# Each module is added as tasks are completed.
# Current: VPC only. EKS, RDS, ElastiCache added in Tasks 11–13.

locals {
  name    = "${var.project}-${var.environment}"
  region  = var.aws_region

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = "10.0.0.0/16"
  az_count           = 3
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  # Dev cost optimization: single NAT GW (~$32/month vs ~$96/month for 3).
  # See ADR-001 for the trade-off analysis.
  single_nat_gateway = true

  cluster_name            = local.name
  flow_log_retention_days = 30

  tags = local.tags
}
