# ─── Root Terragrunt Configuration ───────────────────────────────────────────
# This file is the single source of truth for:
#   - Remote state configuration (S3 bucket, DynamoDB table)
#   - Common provider version constraints
#   - Inputs shared across all environments
#
# Every environment's terragrunt.hcl does `include "root" { path = find_in_parent_folders() }`
# to inherit this config. Environment-specific values override via `inputs = {}`.
#
# WHY TERRAGRUNT?
# Without Terragrunt, every environment copy-pastes the backend config:
#   bucket         = "cloudnative-commerce-tfstate-911788523496"
#   dynamodb_table = "cloudnative-commerce-tfstate-lock"
# Change the bucket name? Update it in 3 places. Miss one? State corruption.
#
# Terragrunt generates backend config dynamically from locals, so the
# bucket name is defined once and injected into every environment.

locals {
  # Parse the environment name from the directory path.
  # e.g. terraform/environments/dev → "dev"
  # e.g. terraform/environments/staging → "staging"
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl", "env.hcl"))
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
  account_id  = local.env_vars.locals.account_id
  project     = "cloudnative-commerce"
}

# ─── Remote State ─────────────────────────────────────────────────────────────
# Dynamically generated backend config — injected into every child module.
# The state key is path-based: environments/dev/terraform.tfstate
# This means each environment gets its own state file automatically.

remote_state {
  backend = "s3"

  config = {
    bucket         = "${local.project}-tfstate-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "${local.project}-tfstate-lock"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ─── Provider Generation ──────────────────────────────────────────────────────
# Terragrunt generates provider.tf so we don't repeat the AWS provider
# configuration in every module. The environment's aws_region and
# default_tags are injected here.

generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Project     = "${local.project}"
          Environment = "${local.environment}"
          ManagedBy   = "terragrunt"
          Repository  = "https://github.com/akshayghalme/cloudnative-commerce"
        }
      }
    }
  EOF
}

# ─── Common Inputs ────────────────────────────────────────────────────────────
# These inputs are available to all child modules that declare matching variables.

inputs = {
  aws_region  = local.aws_region
  environment = local.environment
  project     = local.project
}
