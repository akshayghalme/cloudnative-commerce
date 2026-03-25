output "repository_urls" {
  description = "Map of service name → ECR repository URL. Used in CI/CD to tag and push images."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of service name → ECR repository ARN. Used in IAM policies to grant pull/push access."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_id" {
  description = "ECR registry ID (same as AWS account ID). Used for docker login: aws ecr get-login-password | docker login --username AWS --password-stdin <registry_id>.dkr.ecr.<region>.amazonaws.com"
  value       = data.aws_caller_identity.current.account_id
}

output "registry_url" {
  description = "Base ECR registry URL for docker login"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}
