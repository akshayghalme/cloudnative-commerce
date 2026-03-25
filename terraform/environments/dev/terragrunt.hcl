# ─── Dev Environment Terragrunt Config ───────────────────────────────────────
# Inherits backend + provider from root terragrunt.hcl.
# Defines dev-specific inputs that override root defaults.
#
# Usage:
#   cd terraform/environments/dev
#   terragrunt init      # downloads providers, configures backend
#   terragrunt plan      # shows what will be created
#   terragrunt apply     # creates all resources
#   terragrunt destroy   # tears down everything (DESTRUCTIVE)
#
# For production use, pin the Terragrunt version in your CI pipeline:
#   TERRAGRUNT_VERSION=0.58.0

# Pull in shared config from root terragrunt.hcl
include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env_vars    = read_terragrunt_config("env.hcl")
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
  account_id  = local.env_vars.locals.account_id
}

# ─── Dev-specific inputs ──────────────────────────────────────────────────────
# These override or extend the root inputs {} block.
# Variable names must match variables declared in variables.tf.

inputs = {
  aws_region  = local.aws_region
  environment = local.environment
  project     = "cloudnative-commerce"

  # ── VPC ──
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  single_nat_gateway   = true  # Cost optimization: ~$64/month savings vs 3 NAT GWs

  # ── EKS ──
  cluster_version                      = "1.30"
  node_instance_types                  = ["t3.medium"]
  node_desired_size                    = 2
  node_min_size                        = 1
  node_max_size                        = 3
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # ── RDS ──
  db_instance_class        = "db.t3.micro"
  db_allocated_storage_gb  = 20
  db_multi_az              = false  # Single-AZ in dev, saves ~$13/month
  db_backup_retention_days = 7
  db_deletion_protection   = false
  db_skip_final_snapshot   = true

  # ── ElastiCache ──
  redis_node_type                = "cache.t3.micro"
  redis_num_cache_nodes          = 1
  redis_transit_encryption       = false  # Simplifies debugging; true in prod
  redis_snapshot_retention_limit = 1
}
