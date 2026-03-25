# These ARNs are annotated onto Kubernetes ServiceAccounts.
# The EKS Pod Identity Webhook reads the annotation and injects
# temporary AWS credentials into matching pods automatically.
#
# Kubernetes annotation format:
#   eks.amazonaws.com/role-arn: <role_arn>

output "product_api_role_arn" {
  description = "IRSA role ARN for product-api. Annotate the product-api ServiceAccount with this value."
  value       = aws_iam_role.product_api.arn
}

output "product_api_role_name" {
  description = "IRSA role name for product-api"
  value       = aws_iam_role.product_api.name
}

output "order_worker_role_arn" {
  description = "IRSA role ARN for order-worker. Annotate the order-worker ServiceAccount with this value."
  value       = aws_iam_role.order_worker.arn
}

output "order_worker_role_name" {
  description = "IRSA role name for order-worker"
  value       = aws_iam_role.order_worker.name
}

output "storefront_role_arn" {
  description = "IRSA role ARN for storefront. Annotate the storefront ServiceAccount with this value."
  value       = aws_iam_role.storefront.arn
}

output "storefront_role_name" {
  description = "IRSA role name for storefront"
  value       = aws_iam_role.storefront.name
}
