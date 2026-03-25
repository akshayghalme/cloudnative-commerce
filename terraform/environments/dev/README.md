# Dev Environment

Deploys the full CloudNative Commerce infrastructure to AWS `ap-south-1`.

## Prerequisites

```bash
# Install Terragrunt (manages Terraform with DRY backend config)
brew install terragrunt   # macOS
# or: https://terragrunt.gruntwork.io/docs/getting-started/install/

# AWS credentials configured
aws sts get-caller-identity  # should return account 911788523496
```

## First-time setup

```bash
# 1. Create the S3 bucket + DynamoDB table for remote state
make bootstrap-backend

# 2. Initialize Terragrunt (downloads providers, configures backend)
make tg-init

# 3. Preview what will be created (~40 resources)
make tg-plan

# 4. Apply (takes ~15-20 minutes — EKS cluster creation is slow)
make tg-apply
```

## What gets created

| Resource | Type | ~Cost/month |
|----------|------|-------------|
| VPC + subnets + NAT GW | Networking | $32 |
| EKS cluster (control plane) | Kubernetes | $72 |
| EKS node group (2x t3.medium) | Compute | $60 |
| RDS PostgreSQL (db.t3.micro) | Database | $13 |
| ElastiCache Redis (cache.t3.micro) | Cache | $12 |
| ECR repositories (3) | Registry | ~$1 |
| **Total** | | **~$190/month** |

> **Tip:** Run `terraform destroy` when not actively working to save costs.
> EKS + RDS + ElastiCache charge even when idle.

## After apply — connect kubectl

```bash
aws eks update-kubeconfig \
  --name cloudnative-commerce-dev \
  --region ap-south-1

kubectl get nodes
```

## State location

```
s3://cloudnative-commerce-tfstate-911788523496/
  terraform/environments/dev/terraform.tfstate
```

Lock table: `cloudnative-commerce-tfstate-lock` (DynamoDB)
