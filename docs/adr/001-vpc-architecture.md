# ADR-001: VPC Architecture — 3-AZ Public/Private Layout

**Date:** 2026-03-24
**Status:** Accepted

---

## Context

We need to design the AWS VPC that will host all infrastructure for the CloudNative Commerce
platform: EKS worker nodes, RDS PostgreSQL, ElastiCache Redis, and an Application Load Balancer.

The VPC design is foundational — every other infrastructure decision builds on top of it.
Getting it wrong means expensive rework later (re-IP'ing a live EKS cluster is painful).

Key requirements:
- EKS requires at least 2 AZs; we want real HA so 3 AZs is the target
- Internet-facing traffic must only enter via the ALB — no direct node exposure
- RDS and ElastiCache must never be reachable from the internet
- We need outbound internet access from private subnets (to pull container images, call AWS APIs)
- Cost must be reasonable for a dev environment

---

## Decision

**3-AZ VPC with separate public and private subnets, single NAT Gateway in dev, HA NAT Gateways in prod.**

- CIDR: `10.0.0.0/16` (65,536 IPs — plenty of room to grow)
- 3 public subnets: `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24` (one per AZ)
- 3 private subnets: `10.0.11.0/24`, `10.0.12.0/24`, `10.0.13.0/24` (one per AZ)
- 1 Internet Gateway attached to the VPC
- 1 NAT Gateway in dev (in AZ-a), 3 NAT Gateways in prod (one per AZ)
- VPC Flow Logs enabled → CloudWatch Logs for network auditing

---

## Options Considered

### Option A: Single public subnet (flat network)
- **Pros:** Simple, cheap (no NAT Gateway cost), easy to debug
- **Cons:** RDS and worker nodes are internet-exposed. Fails every security audit.

### Option B: Public + private subnets, single AZ
- **Pros:** Proper public/private separation, cheapest option
- **Cons:** Single AZ = single point of failure. EKS will warn about this. Not a credible HA design.

### Option C: Public + private subnets, 3 AZs, single NAT GW in dev ✅ CHOSEN
- **Pros:** Real HA layout, security best practices, mirrors production VPC design, cost-optimized for dev
- **Cons:** Single NAT GW in dev is a minor HA risk — if that AZ goes down, private subnets lose outbound internet. Acceptable for non-production.

### Option D: Public + private subnets, 3 AZs, 3 NAT Gateways everywhere
- **Pros:** Full HA even in dev
- **Cons:** ~$96/month extra cost for dev with no HA benefit over Option C. Not justified.

---

## Rationale

Option C is the industry-standard VPC layout for EKS workloads. AWS documentation,
the EKS Best Practices Guide, and every well-architected review recommend this pattern.

The public/private split is non-negotiable for security:
- ALB lives in public subnets — it's the only thing that should be internet-reachable
- EKS nodes, RDS, and Redis live in private subnets — they should never have public IPs
- NAT Gateway allows private resources to initiate outbound connections (pull images, call APIs)
  without being reachable inbound

The 3-AZ layout is required because:
- EKS managed node groups need multi-AZ to properly spread pods
- RDS Multi-AZ standby needs to be in a different AZ than the primary
- The system must survive an AZ failure without operator intervention

The single NAT GW in dev saves ~$64/month (NAT GW is $0.045/hr + data processing charges).
The risk is acceptable: if AZ-a goes down in dev, nodes in AZ-b and AZ-c lose outbound internet
until we notice and fix it. In prod, that's unacceptable — so we use 3.

---

## Consequences

### Positive
- Security: RDS and EKS nodes are never internet-exposed
- HA: Any single AZ failure leaves 2 AZs operational
- Scalability: /16 CIDR gives us room for hundreds of subnets if needed
- Auditability: VPC Flow Logs capture all traffic for security investigations
- Industry standard: Any AWS engineer will immediately understand this layout

### Negative
- Cost: NAT Gateway adds ~$32/month in dev (1 NAT GW + data transfer)
- Complexity: Routing tables for public vs private subnets must be correctly configured
- NAT GW single point of failure in dev (accepted risk)

### Risks
- Subnet exhaustion: /24 subnets give 251 usable IPs each. If pod density exceeds 251 per AZ per subnet, expansion requires re-IP or additional subnets.
- CIDR conflicts: 10.0.0.0/16 could conflict with on-prem networks if VPN/Direct Connect
  is added later. Document this as a known limitation.

---

## Implementation Notes

Terraform module will be created at `terraform/modules/vpc/` with:
- `main.tf` — VPC, subnets, IGW, NAT GW, route tables
- `variables.tf` — CIDR blocks, AZ list, environment name
- `outputs.tf` — VPC ID, subnet IDs (for use by EKS, RDS modules)

Subnet tagging is critical for EKS:
```hcl
# Public subnets — ALB auto-discovery
"kubernetes.io/role/elb" = "1"

# Private subnets — internal ALB + EKS node auto-discovery
"kubernetes.io/role/internal-elb"             = "1"
"kubernetes.io/cluster/${var.cluster_name}"   = "owned"
```

Without these tags, EKS cannot automatically place load balancers in the right subnets.

---

## References

- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [EKS VPC Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [EKS Best Practices Guide — Networking](https://aws.github.io/aws-eks-best-practices/networking/index/)
- [NAT Gateway pricing](https://aws.amazon.com/vpc/pricing/)
