terraform {
  # Minimum Terraform version — enforces consistent CLI across the team.
  # 1.9+ required for provider-defined functions used in later modules.
  required_version = ">= 1.9.0"

  required_providers {
    # AWS provider — pinned to a minor version range.
    # Patch updates (5.x.y) are allowed; minor bumps require an explicit PR.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }

    # Kubernetes provider — used when configuring the EKS cluster post-creation
    # (e.g. aws-auth ConfigMap, namespace bootstrapping)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }

    # Helm provider — used to deploy platform components (Karpenter, cert-manager,
    # ingress-nginx) directly from Terraform rather than ArgoCD, so the cluster
    # bootstraps cleanly on first apply.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }

    # TLS provider — used to generate the KMS key policy and for self-signed
    # certs during bootstrap only.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Random provider — generates the RDS master password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
