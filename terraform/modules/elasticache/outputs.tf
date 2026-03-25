# Outputs consumed by:
#   - Kubernetes ConfigMap / ExternalSecret: redis_endpoint for app config
#   - IAM/IRSA module (Task 14): redis_security_group_id for ingress rules

output "redis_cluster_id" {
  description = "ElastiCache cluster ID"
  value       = aws_elasticache_cluster.this.id
}

output "redis_endpoint" {
  description = "Redis primary endpoint address — use this in application connection strings"
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port (always 6379)"
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "redis_connection_string" {
  description = "Full Redis connection string in redis:// format for application config"
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:6379"
}

output "redis_security_group_id" {
  description = "Security group ID for Redis — add to ingress rules for any additional clients"
  value       = aws_security_group.redis.id
}

output "redis_subnet_group_name" {
  description = "ElastiCache subnet group name"
  value       = aws_elasticache_subnet_group.this.name
}

output "redis_parameter_group_name" {
  description = "ElastiCache parameter group name"
  value       = aws_elasticache_parameter_group.this.name
}
