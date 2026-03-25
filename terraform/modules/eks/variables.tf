variable "cluster_name" {
  description = "Name of the EKS cluster. Also used in IAM role names and resource tags."
  type        = string
}

variable "cluster_version" {
  description = <<-EOT
    Kubernetes version for the EKS control plane.
    Pin this explicitly — never use 'latest'. EKS supports each minor version
    for ~14 months. Upgrades are a deliberate PR, not a silent drift.

    Check supported versions: aws eks describe-addon-versions
  EOT
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created. From module.vpc.vpc_id."
  type        = string
}

variable "private_subnet_ids" {
  description = <<-EOT
    Private subnet IDs for EKS node groups. From module.vpc.private_subnet_ids.
    Must be in at least 2 AZs; 3 AZs recommended for production HA.
    Subnets must have the kubernetes.io/cluster/<name> tag (set by VPC module).
  EOT
  type        = list(string)
}

variable "node_instance_types" {
  description = <<-EOT
    EC2 instance types for the managed node group.
    Providing multiple types enables instance flexibility — if one type is
    unavailable in an AZ, EKS can use another. Karpenter (Task 22) will
    eventually take over node provisioning; this node group is the bootstrap floor.
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes. Set to 2 for HA (one per AZ minimum)."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes. HPA scales pods; node group scales for Karpenter overflow."
  type        = number
  default     = 3
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size in GB for each node. 50GB covers OS + container images."
  type        = number
  default     = 50
}

variable "cluster_endpoint_private_access" {
  description = <<-EOT
    Enable private API server endpoint (accessible from within VPC).
    Should be true — kubectl from CI/CD runners inside the VPC uses this.
  EOT
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = <<-EOT
    Enable public API server endpoint (accessible from internet).
    True for dev (developer laptops need kubectl access).
    In prod, consider restricting to specific CIDRs or disabling entirely.
  EOT
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API server endpoint.
    Default 0.0.0.0/0 is acceptable for dev; restrict to office/VPN CIDRs in prod.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_log_types" {
  description = <<-EOT
    EKS control plane log types to send to CloudWatch.
    - api: API server audit logs (who did what)
    - audit: Kubernetes audit logs
    - authenticator: aws-iam-authenticator logs
    - controllerManager: controller reconciliation logs
    - scheduler: pod scheduling decisions
  EOT
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
