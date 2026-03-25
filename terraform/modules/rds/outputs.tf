# Outputs consumed by:
#   - IAM/IRSA module (Task 14): needs db_secret_arn for product-api IRSA policy
#   - Kubernetes ExternalSecret (Task 26): pulls credentials from Secrets Manager
#   - Application config: db_address and db_port for connection strings

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.this.arn
}

output "db_address" {
  description = "RDS endpoint hostname — use this in application connection strings (not the IP)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port (always 5432 for PostgreSQL)"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "db_security_group_id" {
  description = "Security group ID for the RDS instance — add to ingress rules if other services need DB access"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}

output "db_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret containing master credentials.
    The product-api IRSA role needs GetSecretValue permission on this ARN.
    Format: { username, password, host, port, dbname, url }
  EOT
  value       = aws_secretsmanager_secret.rds_master.arn
}

output "db_secret_name" {
  description = "Secrets Manager secret name — used by ExternalSecrets operator to sync to Kubernetes Secrets"
  value       = aws_secretsmanager_secret.rds_master.name
}
