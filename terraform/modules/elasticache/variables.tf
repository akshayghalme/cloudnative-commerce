variable "name" {
  description = "Name prefix for all ElastiCache resources (e.g. 'cloudnative-commerce-dev')"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ElastiCache will be created. From module.vpc.vpc_id."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ElastiCache subnet group. From module.vpc.private_subnet_ids."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to Redis on port 6379. Typically the EKS node security group."
  type        = list(string)
}

variable "node_type" {
  description = <<-EOT
    ElastiCache node type.
    Dev: cache.t3.micro (~$12/month) — minimal, sufficient for sessions and light caching.
    Prod: cache.r6g.large for memory-intensive workloads.
  EOT
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Redis engine version. Pin explicitly — never use 'latest'."
  type        = string
  default     = "7.1"
}

variable "num_cache_nodes" {
  description = <<-EOT
    Number of cache nodes.
    Dev: 1 (no replication — single point of failure, acceptable for non-prod).
    Prod: use a replication group with 2+ nodes instead (see num_replicas).
  EOT
  type        = number
  default     = 1
}

variable "parameter_group_family" {
  description = "Redis parameter group family — must match engine_version major.minor."
  type        = string
  default     = "redis7"
}

variable "at_rest_encryption_enabled" {
  description = "Encrypt data at rest. Always true — sessions and cache may contain sensitive user data."
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = <<-EOT
    Encrypt data in transit (TLS). True in prod.
    In dev, false simplifies local debugging (redis-cli without TLS flags).
    When true, clients must connect with TLS and auth token is required.
  EOT
  type        = bool
  default     = false
}

variable "auth_token" {
  description = "Auth token (password) for Redis AUTH command. Required when transit_encryption_enabled = true. Leave empty for dev."
  type        = string
  default     = ""
  sensitive   = true
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain Redis snapshots. 0 disables snapshots (acceptable for cache-only use cases)."
  type        = number
  default     = 1
}

variable "snapshot_window" {
  description = "Daily time window for Redis snapshots (UTC)."
  type        = string
  default     = "05:00-06:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window for Redis patching."
  type        = string
  default     = "sun:06:00-sun:07:00"
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor Redis version upgrades during maintenance windows."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
