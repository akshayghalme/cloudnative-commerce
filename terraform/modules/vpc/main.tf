# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Required for EKS — nodes and pods need DNS resolution inside the VPC.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

# ─── Availability Zones ───────────────────────────────────────────────────────

# Fetch available AZs in the region at plan time.
# We slice to exactly var.az_count (3) to stay predictable.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Derive subnet names from AZ suffixes (ap-south-1a → "a")
  az_suffixes = [for az in local.azs : substr(az, -1, 1)]
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

# ─── Public Subnets ───────────────────────────────────────────────────────────
# One per AZ — used by ALB and NAT Gateways only.
# EKS nodes and application workloads NEVER go here.

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Instances launched here get a public IP automatically.
  # Required for NAT Gateway ENIs.
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${local.az_suffixes[count.index]}"
    Tier = "public"

    # EKS tag — tells the AWS Load Balancer Controller to place
    # internet-facing ALBs in these subnets automatically.
    "kubernetes.io/role/elb" = "1"

    # EKS cluster ownership tag — required when multiple clusters share a VPC.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ─── Private Subnets ──────────────────────────────────────────────────────────
# One per AZ — EKS nodes, RDS, ElastiCache, and pods all live here.
# No direct internet access; outbound goes through NAT Gateway.

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Private subnets never assign public IPs — that's the point.
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${local.az_suffixes[count.index]}"
    Tier = "private"

    # EKS tag — tells the AWS Load Balancer Controller to place
    # internal ALBs in these subnets.
    "kubernetes.io/role/internal-elb" = "1"

    # EKS cluster ownership tag — Karpenter uses this to discover
    # which subnets to launch nodes into.
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"

    # Karpenter discovery tag — NodePool uses this label selector.
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# ─── Elastic IPs for NAT Gateways ────────────────────────────────────────────

resource "aws_eip" "nat" {
  # In dev: 1 EIP (one NAT GW). In prod: 3 EIPs (one per AZ).
  count  = var.single_nat_gateway ? 1 : var.az_count
  domain = "vpc"

  # EIP must not be released before the IGW is detached.
  depends_on = [aws_internet_gateway.this]

  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip-${count.index + 1}"
  })
}

# ─── NAT Gateways ────────────────────────────────────────────────────────────
# Dev: single NAT GW in AZ-a (saves ~$64/month, see ADR-001)
# Prod: one per AZ for full HA

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : var.az_count

  allocation_id = aws_eip.nat[count.index].id

  # Always place in a public subnet (NAT GW needs internet access).
  # Single NAT: always public subnet 0 (AZ-a). Multi-NAT: one per AZ.
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ─── Route Tables — Public ───────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─── Route Tables — Private ──────────────────────────────────────────────────
# One route table per private subnet.
# Dev: all 3 route tables point to the single NAT GW.
# Prod: each route table points to the NAT GW in its own AZ.

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${local.az_suffixes[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────────
# Captures all accepted/rejected traffic in and out of the VPC.
# Critical for: security investigations, compliance audits, debugging
# network connectivity issues between services.

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.name}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name}-flow-logs"
  })
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL" # Capture ACCEPT and REJECT — both are useful
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = merge(var.tags, {
    Name = "${var.name}-flow-log"
  })
}
