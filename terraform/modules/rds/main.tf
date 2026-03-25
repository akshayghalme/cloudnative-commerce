# ─── Random Password ──────────────────────────────────────────────────────────
# Generate a strong master password and store it in AWS Secrets Manager.
# The application never uses the master password directly — it uses a
# dedicated application user created via a migration script.

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  # Force a new password only if the instance is replaced.
  lifecycle {
    ignore_changes = [special, override_special]
  }
}

resource "aws_secretsmanager_secret" "rds_master" {
  name        = "${var.name}/rds/master-credentials"
  description = "RDS master credentials for ${var.name}. Application services use app-level credentials, not this."

  # Allow recovery within 7 days if accidentally deleted.
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id

  secret_string = jsonencode({
    username = var.database_username
    password = random_password.master.result
    host     = aws_db_instance.this.address
    port     = 5432
    dbname   = var.database_name
    # Full connection string for convenience
    url = "postgresql://${var.database_username}:${random_password.master.result}@${aws_db_instance.this.address}:5432/${var.database_name}"
  })
}

# ─── Security Group ───────────────────────────────────────────────────────────
# Only allows inbound on port 5432 from specified security groups (EKS nodes).
# No direct internet access — RDS is in private subnets.

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Security group for RDS PostgreSQL — allows inbound 5432 from EKS nodes only"
  vpc_id      = var.vpc_id

  # Allow PostgreSQL access from EKS node security groups.
  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = ingress.value
      description              = "PostgreSQL from EKS nodes"
    }
  }

  # Egress not needed for RDS, but explicit deny would block CloudWatch/Secrets Manager
  # connectivity which some enhanced monitoring features require.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (required for enhanced monitoring)"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-rds-sg"
  })
}

# ─── DB Subnet Group ──────────────────────────────────────────────────────────
# RDS requires a subnet group spanning at least 2 AZs.
# We always use all 3 private subnets so Multi-AZ failover has the
# maximum number of target AZs to choose from.

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-rds-subnet-group"
  description = "Private subnets for RDS PostgreSQL — no internet access"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-rds-subnet-group"
  })
}

# ─── Parameter Group ──────────────────────────────────────────────────────────
# Custom parameter group lets us tune PostgreSQL without recreating the instance.
# Key parameters set here improve performance and observability.

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-postgres16"
  family      = "postgres16"
  description = "Custom parameter group for ${var.name} PostgreSQL 16"

  # Enable query logging — critical for debugging slow queries in dev.
  # In prod, set log_min_duration_statement to 1000ms to avoid log spam.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking longer than 1 second
  }

  # Log connection attempts — useful for detecting connection pool exhaustion.
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Log lock waits — helps diagnose deadlocks between services.
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  # Shared buffers — PostgreSQL's main memory cache.
  # Default is 128MB; 256MB is better for t3.micro.
  # For larger instance classes, set to 25% of RAM.
  parameter {
    name         = "shared_buffers"
    value        = "131072" # 128MB in 8KB pages (131072 * 8KB = 1GB)
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-postgres16-params"
  })
}

# ─── RDS Instance ─────────────────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = var.name

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage — gp3 is newer and faster than gp2 at the same price point.
  # Storage autoscaling prevents out-of-space incidents.
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_encrypted     = true # Encrypt at rest — non-negotiable

  # Credentials
  db_name  = var.database_name
  username = var.database_username
  password = random_password.master.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Never expose RDS directly to the internet

  # Parameter group
  parameter_group_name = aws_db_parameter_group.this.name

  # High Availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  copy_tags_to_snapshot   = true

  # Maintenance
  maintenance_window          = var.maintenance_window
  auto_minor_version_upgrade  = true  # Patch versions auto-upgrade (safe)
  allow_major_version_upgrade = false # Major versions are explicit — breaking changes

  # Performance Insights — free for 7 days retention, invaluable for query analysis.
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced monitoring — 60-second granularity OS metrics in CloudWatch.
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  # Deletion protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"

  tags = merge(var.tags, {
    Name = var.name
  })

  # Password is managed by Secrets Manager — don't show in plan diffs.
  lifecycle {
    ignore_changes = [password]
  }
}

# ─── IAM Role — Enhanced Monitoring ──────────────────────────────────────────
# Enhanced monitoring streams OS-level metrics (CPU steal, disk I/O, swap)
# to CloudWatch at 60-second intervals. These metrics aren't available via
# standard CloudWatch — they come from an agent running on the RDS host.

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
