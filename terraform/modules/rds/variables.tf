variable "name" {
  description = "Name prefix for all RDS resources (e.g. 'cloudnative-commerce-dev')"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RDS will be created. From module.vpc.vpc_id."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group. From module.vpc.private_subnet_ids. Minimum 2 subnets in different AZs required."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to RDS on port 5432. Typically the EKS node security group."
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block — used to restrict RDS ingress to intra-VPC traffic only."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version. Pin to a specific minor version to avoid surprise upgrades."
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = <<-EOT
    RDS instance class.
    Dev: db.t3.micro (~$13/month) — minimal, free tier eligible.
    Prod: db.t3.medium or db.r6g.large for production workloads.
  EOT
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Initial EBS storage allocated in GB. RDS autoscaling can grow this up to max_allocated_storage_gb."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage RDS can autoscale to. Prevents runaway storage costs."
  type        = number
  default     = 100
}

variable "database_name" {
  description = "Name of the initial database to create."
  type        = string
  default     = "commerce"
}

variable "database_username" {
  description = "Master username for the RDS instance. Do not use 'admin' or 'postgres' — reserved words."
  type        = string
  default     = "commerce_admin"
}

variable "multi_az" {
  description = <<-EOT
    Enable Multi-AZ deployment for high availability.
    Dev: false (saves ~$13/month — single AZ is acceptable for non-prod).
    Prod: true (standby replica in a different AZ, automatic failover in <60s).
  EOT
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups. Minimum 7 for prod. 1 is acceptable for dev."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "backup_window" {
  description = "Daily time window for automated backups (UTC). Should not overlap with maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly time window for maintenance (patching). Format: ddd:hh24:mi-ddd:hh24:mi."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the RDS instance. Always true in prod; false in dev for easy teardown."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion. True in dev (quick teardown); false in prod (always snapshot before delete)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
