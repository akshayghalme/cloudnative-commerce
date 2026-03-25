provider "aws" {
  region = var.aws_region

  # Default tags applied to EVERY resource created by this provider.
  # This is a best practice — it means cost allocation, ownership, and
  # environment are always queryable in AWS Cost Explorer and Config.
  default_tags {
    tags = {
      Project     = "cloudnative-commerce"
      Environment = "dev"
      ManagedBy   = "terraform"
      Repository  = "https://github.com/akshayghalme/cloudnative-commerce"
    }
  }
}

# Secondary provider alias for resources that must be in us-east-1
# regardless of the primary region (e.g. ACM certs for CloudFront).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "cloudnative-commerce"
      Environment = "dev"
      ManagedBy   = "terraform"
      Repository  = "https://github.com/akshayghalme/cloudnative-commerce"
    }
  }
}

# Kubernetes and Helm providers are configured after EKS is created.
# They reference EKS module outputs so the cluster must exist first.
# See main.tf for the provider configuration blocks.
