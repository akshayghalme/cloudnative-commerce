variable "cluster_name" {
  description = "EKS cluster name. Used in IAM role names for clarity."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC identity provider. From module.eks.oidc_provider_arn. Required for IRSA trust policies."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https://. From module.eks.oidc_provider_url. Used in IAM condition keys."
  type        = string
}

# ─── product-api permissions ──────────────────────────────────────────────────

variable "product_api_namespace" {
  description = "Kubernetes namespace where product-api runs."
  type        = string
  default     = "commerce"
}

variable "product_api_service_account" {
  description = "Kubernetes ServiceAccount name for product-api."
  type        = string
  default     = "product-api"
}

variable "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret containing RDS credentials. From module.rds.db_secret_arn. Granted to product-api IRSA role."
  type        = string
}

# ─── order-worker permissions ─────────────────────────────────────────────────

variable "order_worker_namespace" {
  description = "Kubernetes namespace where order-worker runs."
  type        = string
  default     = "commerce"
}

variable "order_worker_service_account" {
  description = "Kubernetes ServiceAccount name for order-worker."
  type        = string
  default     = "order-worker"
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS orders queue. Granted to order-worker IRSA role."
  type        = string
  default     = "*" # Overridden once SQS queue is created
}

variable "sqs_dlq_arn" {
  description = "ARN of the SQS dead-letter queue. Granted to order-worker IRSA role."
  type        = string
  default     = "*" # Overridden once SQS DLQ is created
}

# ─── storefront permissions ───────────────────────────────────────────────────

variable "storefront_namespace" {
  description = "Kubernetes namespace where storefront runs."
  type        = string
  default     = "commerce"
}

variable "storefront_service_account" {
  description = "Kubernetes ServiceAccount name for storefront."
  type        = string
  default     = "storefront"
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
