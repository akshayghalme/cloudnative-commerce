# Outputs consumed by other modules:
#   - EKS module: needs vpc_id, private_subnet_ids, public_subnet_ids
#   - RDS module: needs vpc_id, private_subnet_ids, vpc_cidr_block
#   - ElastiCache module: needs vpc_id, private_subnet_ids
#   - Security group modules: need vpc_id for ingress/egress rules

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC — used by security groups to allow intra-VPC traffic"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (one per AZ) — used by ALB and NAT Gateways"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (one per AZ) — used by EKS nodes, RDS, ElastiCache"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (1 in dev, 3 in prod)"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of NAT Gateways — add these to external allowlists if needed"
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "private_route_table_ids" {
  description = "IDs of private route tables — used when adding VPC endpoints (S3, ECR, etc.)"
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "availability_zones" {
  description = "List of AZs used by this VPC — passed to EKS and RDS modules"
  value       = local.azs
}
