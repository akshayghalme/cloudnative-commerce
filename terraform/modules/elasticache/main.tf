# ─── Security Group ───────────────────────────────────────────────────────────
# Only allows inbound on port 6379 from EKS nodes.
# Redis is in private subnets — never internet-accessible.

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis-sg"
  description = "Security group for ElastiCache Redis — allows inbound 6379 from EKS nodes only"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = ingress.value
      description              = "Redis from EKS nodes"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-redis-sg"
  })
}

# ─── Subnet Group ─────────────────────────────────────────────────────────────
# ElastiCache subnet group spanning all 3 private AZs.
# Even with num_cache_nodes = 1, the subnet group must span multiple AZs
# so AWS can place the node in any AZ during replacement/maintenance.

resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name}-redis-subnet-group"
  description = "Private subnets for ElastiCache Redis — no internet access"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-redis-subnet-group"
  })
}

# ─── Parameter Group ──────────────────────────────────────────────────────────
# Custom parameter group for Redis tuning.
# Key settings: maxmemory policy (what to evict when memory is full)
# and slowlog (equivalent to PostgreSQL's slow query log).

resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.name}-redis7"
  family      = var.parameter_group_family
  description = "Custom Redis 7 parameter group for ${var.name}"

  # allkeys-lru: evict least-recently-used keys when memory is full.
  # Best policy for a general-purpose cache where you don't want OOM errors.
  # Alternative: volatile-lru (only evict keys with TTL set) — use if you
  # store persistent data alongside cached data in the same cluster.
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Log commands that take longer than 10ms (10000 microseconds).
  # Inspect with: redis-cli SLOWLOG GET 10
  parameter {
    name  = "slowlog-log-slower-than"
    value = "10000"
  }

  # Keep the last 128 slow commands in the slowlog ring buffer.
  parameter {
    name  = "slowlog-max-len"
    value = "128"
  }

  # Lazyfree: delete large keys asynchronously to avoid blocking the event loop.
  # Without this, DEL on a large hash/list can block Redis for milliseconds.
  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  parameter {
    name  = "lazyfree-lazy-expire"
    value = "yes"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-redis7-params"
  })
}

# ─── ElastiCache Cluster ──────────────────────────────────────────────────────
# Single-node Redis cluster for dev. In production, use
# aws_elasticache_replication_group with cluster_mode_enabled = true
# for Multi-AZ with automatic failover.
#
# Why not replication group here?
# - Replication group requires 2+ nodes — minimum ~$24/month
# - For dev, a single cache.t3.micro at ~$12/month is sufficient
# - The application code is the same regardless of cluster topology

resource "aws_elasticache_cluster" "this" {
  cluster_id = var.name

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]
  port                 = 6379

  # Encryption
  at_rest_encryption_enabled = var.at_rest_encryption_enabled

  # Snapshots — even for a cache, daily snapshots let you restore
  # session data after a catastrophic failure.
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Apply changes immediately in dev. In prod, set to false so changes
  # apply during the maintenance window (avoids mid-day cache flush).
  apply_immediately = true

  tags = merge(var.tags, {
    Name = var.name
  })
}
