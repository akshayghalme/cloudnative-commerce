variable "name" {
  description = "Name prefix for all VPC resources (e.g. 'cloudnative-commerce-dev')"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be /16 or larger for EKS workloads."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. '10.0.0.0/16')"
  }
}

variable "az_count" {
  description = "Number of availability zones to use. Must be 3 for production HA."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3. EKS requires at least 2; 3 is recommended for production."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ. Used by ALB and NAT Gateways."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 3
    error_message = "Must provide at least 3 public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ. Used by EKS nodes, RDS, ElastiCache."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 3
    error_message = "Must provide at least 3 private subnet CIDRs."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    If true, deploy a single NAT Gateway in AZ-a (dev cost optimization).
    If false, deploy one NAT Gateway per AZ (production HA).

    Trade-off: single NAT GW saves ~$64/month but creates an AZ-a dependency
    for private subnet outbound traffic. Acceptable for dev; not for prod.
    See ADR-001 for full analysis.
  EOT
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = <<-EOT
    EKS cluster name. Used in subnet tags so the AWS Load Balancer Controller
    and Karpenter can discover the correct subnets automatically.

    Tags applied:
      Public subnets:  kubernetes.io/cluster/<cluster_name> = "shared"
      Private subnets: kubernetes.io/cluster/<cluster_name> = "owned"
                       karpenter.sh/discovery               = <cluster_name>
  EOT
  type        = string
  default     = "cloudnative-commerce"
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC flow logs in CloudWatch. 30 days covers most incident investigations."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a valid CloudWatch log retention value."
  }
}

variable "tags" {
  description = "Additional tags to merge onto all resources. The provider's default_tags already include Project, Environment, ManagedBy, Repository."
  type        = map(string)
  default     = {}
}
