# env.hcl — environment-specific values read by the root terragrunt.hcl.
# This file is NOT a terragrunt config itself — it's a data file read
# via read_terragrunt_config() in the root.
#
# Keeping account_id and aws_region here (not in terragrunt.hcl) means:
#   - Adding a staging environment = copy this file, change values
#   - No root config changes needed
#   - Different environments can target different AWS accounts

locals {
  environment = "dev"
  aws_region  = "ap-south-1"
  account_id  = "911788523496"
}
