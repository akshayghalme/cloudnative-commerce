# Outputs consumed by other modules and the environment main.tf:
#   - Karpenter module: needs cluster_name, oidc_provider_arn, node_role_arn
#   - IAM module (IRSA roles): needs oidc_provider_arn, oidc_provider_url
#   - ArgoCD / kubectl: needs cluster_endpoint, cluster_certificate_authority_data
#   - Helm/Kubernetes providers: need cluster_endpoint + CA data

output "cluster_id" {
  description = "EKS cluster ID (same as cluster_name for AWS)"
  value       = aws_eks_cluster.this.id
}

output "cluster_name" {
  description = "EKS cluster name — used by kubectl, Karpenter, and ArgoCD"
  value       = aws_eks_cluster.this.name
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  description = "API server endpoint URL — used to configure kubectl and Helm/Kubernetes Terraform providers"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data — used to verify the API server TLS cert"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID for the managed node group — add rules here for RDS/ElastiCache access"
  value       = aws_security_group.nodes.id
}

output "node_role_arn" {
  description = "IAM role ARN for the node group — Karpenter needs this to launch nodes"
  value       = aws_iam_role.nodes.arn
}

output "node_role_name" {
  description = "IAM role name for the node group"
  value       = aws_iam_role.nodes.name
}

output "oidc_provider_arn" {
  description = <<-EOT
    ARN of the OIDC identity provider — used in IRSA trust policies.
    Every IAM role for a service account (IRSA) needs this ARN in its
    assume_role_policy to trust tokens from this cluster.
  EOT
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (without https://) — used in IRSA condition keys"
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Kubernetes secrets at rest"
  value       = aws_kms_key.eks.arn
}

output "cluster_log_group_name" {
  description = "CloudWatch log group name for EKS control plane logs"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}
