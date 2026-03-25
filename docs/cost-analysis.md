# Cost Analysis — CloudNative Commerce

**Last updated:** 2026-03-25
**Region:** ap-south-1 (Mumbai)
**Pricing:** AWS on-demand, USD, as of March 2026

---

## Executive Summary

| Environment | Monthly Cost | Savings Applied |
|-------------|-------------|-----------------|
| **Dev** | ~$147/mo | Single NAT GW, Spot nodes, single-AZ RDS |
| **Staging** | ~$195/mo | Spot nodes, single-AZ RDS |
| **Prod** | ~$580/mo | Multi-AZ RDS, On-Demand nodes, HA |
| **Total** | **~$922/mo** | |

Dev is optimized aggressively for cost. Prod is optimized for reliability.

---

## Dev Environment Breakdown

### Compute — EKS + EC2 Nodes

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| EKS control plane | 1 cluster | $73.00 | Fixed cost, no way to reduce |
| Managed node group | 2x t3.medium (baseline) | $60.74 | $0.0416/hr × 2 × 730h |
| Karpenter Spot nodes | ~1x t3.medium (avg) | ~$12.00 | ~80% savings vs on-demand |
| **Subtotal** | | **$145.74** | |

> **Why t3.medium:** 2 vCPU / 4 GiB fits 3 services + platform components.
> t3.small (2 vCPU / 2 GiB) is too tight after kubelet + daemonsets reserve ~500 MiB.

### Database — RDS PostgreSQL

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| RDS instance | db.t4g.micro, single-AZ | $12.41 | $0.017/hr × 730h |
| Storage | 20 GiB gp3 | $2.30 | $0.115/GiB/mo |
| Backups | 7-day retention (included) | $0.00 | First backup = free |
| **Subtotal** | | **$14.71** | |

> **Dev trade-off:** single-AZ saves ~$12/mo but has no failover.
> Acceptable for dev — data loss risk is low, and we can recreate from migrations.

### Cache — ElastiCache Redis

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| Redis node | cache.t4g.micro, single-node | $10.22 | $0.014/hr × 730h |
| **Subtotal** | | **$10.22** | |

### Networking

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| NAT Gateway | 1 (single AZ) | $32.85 | $0.045/hr × 730h |
| NAT data processing | ~10 GB/mo | $0.45 | $0.045/GB |
| VPC Flow Logs | ~5 GB/mo to CloudWatch | $2.50 | $0.50/GB ingestion |
| Load Balancer (NLB) | 1 | $16.43 | $0.0225/hr × 730h |
| NLB data processing | ~10 GB/mo | $0.10 | $0.01/GB |
| **Subtotal** | | **$52.33** | |

> **Single NAT Gateway:** saves $32.85/mo vs HA (one per AZ). Risk: if the
> NAT GW's AZ goes down, nodes in other AZs lose internet access. Acceptable
> for dev — ECR pulls and AWS API calls fail, but the cluster continues running.

### Storage — ECR + S3

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| ECR | 3 repos, ~5 GB total | $0.50 | $0.10/GB/mo |
| S3 (Terraform state) | < 1 GB | $0.02 | Negligible |
| EBS (Prometheus PV) | 50 GiB gp3 | $4.60 | $0.092/GiB/mo |
| EBS (Loki PV) | 50 GiB gp3 | $4.60 | $0.092/GiB/mo |
| EBS (Tempo PV) | 30 GiB gp3 | $2.76 | $0.092/GiB/mo |
| **Subtotal** | | **$12.48** | |

### Monitoring + Observability

| Resource | Spec | Monthly Cost | Notes |
|----------|------|-------------|-------|
| CloudWatch Logs (EKS) | ~5 GB/mo | $2.50 | EKS control plane logs |
| CloudWatch Metrics (RDS) | Standard | $0.00 | Included with RDS |
| **Subtotal** | | **$2.50** | |

> Prometheus/Grafana/Loki run on the cluster — no additional AWS cost beyond
> the EBS volumes (already counted above).

### Dev Total

| Category | Monthly Cost | % of Total |
|----------|-------------|------------|
| Compute (EKS + nodes) | $145.74 | 61% |
| Networking (NAT + NLB) | $52.33 | 22% |
| Database (RDS) | $14.71 | 6% |
| Storage (ECR + EBS) | $12.48 | 5% |
| Cache (Redis) | $10.22 | 4% |
| Monitoring (CloudWatch) | $2.50 | 1% |
| **Total** | **~$238** | |

> Note: The README states ~$147/mo which was the original estimate without
> observability storage. The full stack with Prometheus/Loki/Tempo PVs is ~$238/mo.

---

## Prod Environment Breakdown

| Category | Dev Cost | Prod Cost | Why the increase |
|----------|---------|-----------|-----------------|
| EKS control plane | $73.00 | $73.00 | Same |
| EC2 nodes | $72.74 | $182.00 | 3x on-demand (no Spot), larger instances |
| RDS | $14.71 | $50.00 | db.t4g.small, Multi-AZ |
| ElastiCache | $10.22 | $20.44 | 2-node replication group |
| NAT Gateway | $32.85 | $98.55 | 3 NAT GWs (one per AZ, HA) |
| NLB | $16.43 | $16.43 | Same |
| Storage | $12.48 | $25.00 | Larger PVs, more ECR images |
| CloudWatch | $2.50 | $5.00 | More log volume |
| **Total** | **~$238** | **~$470** | |

---

## Cost Optimization Strategies

### Already implemented (dev)

| Strategy | Savings | How |
|----------|---------|-----|
| Single NAT Gateway | $65/mo | 1 NAT GW vs 3 |
| Spot instances (Karpenter) | ~$50/mo | 60-80% discount on workload nodes |
| Single-AZ RDS | ~$12/mo | No standby replica |
| t4g.micro RDS/Redis | ~$30/mo | Graviton, smallest instance |
| gp3 volumes | ~$5/mo | 20% cheaper than gp2, better IOPS |

### Available optimizations (not yet implemented)

| Strategy | Potential Savings | Trade-off |
|----------|------------------|-----------|
| **Graviton nodes (ARM)** | 20% on EC2 | Requires multi-arch Docker images |
| **Reserved Instances (1yr)** | 30-40% on EC2/RDS | Commitment, less flexibility |
| **Savings Plans** | 20-30% on compute | 1-year commitment |
| **Karpenter consolidation** | Variable | Already enabled — auto-right-sizes |
| **Spot for staging** | ~$40/mo | Acceptable — staging can tolerate interruptions |
| **Turn off dev at night** | ~40% | Scheduled scaling to 0 nodes, 8pm-8am |
| **EBS snapshot lifecycle** | ~$3/mo | Delete old snapshots > 30 days |
| **S3 Intelligent Tiering** | Negligible | Only for large datasets |

### Cost monitoring

| Tool | What it tracks |
|------|---------------|
| Grafana Cost Dashboard | CPU/memory utilization efficiency, over-provisioned pods |
| AWS Cost Explorer | Per-service AWS spend, daily trends |
| Karpenter consolidation | Automatic right-sizing and bin-packing |
| kubecost (optional) | Per-namespace, per-pod cost attribution |

---

## Cost by Service (estimated pod resource cost)

Based on CPU/memory requests mapped to t3.medium pricing:

| Service | CPU Request | Memory Request | Est. Monthly Cost |
|---------|-----------|---------------|-------------------|
| product-api (2 replicas) | 200m | 256Mi | ~$6.00 |
| storefront (2 replicas) | 200m | 256Mi | ~$6.00 |
| order-worker (2 replicas) | 200m | 256Mi | ~$6.00 |
| Prometheus | 500m | 1Gi | ~$8.00 |
| Grafana | 100m | 256Mi | ~$2.00 |
| Loki | 200m | 256Mi | ~$3.00 |
| OTel Collector (2 replicas) | 400m | 512Mi | ~$5.00 |
| Tempo | 200m | 256Mi | ~$3.00 |
| ingress-nginx (2 replicas) | 200m | 256Mi | ~$3.00 |
| cert-manager | 100m | 128Mi | ~$1.50 |
| ArgoCD (5 pods) | 500m | 1Gi | ~$8.00 |
| Karpenter | 200m | 256Mi | ~$3.00 |
| Kyverno | 200m | 256Mi | ~$3.00 |
| **Total platform overhead** | **~3.2 CPU** | **~5 GiB** | **~$57/mo** |

> Platform components consume ~3.2 vCPU / 5 GiB — roughly 1.5 t3.medium nodes
> just for infrastructure. This is the "cost of production-grade" — monitoring,
> security, and GitOps aren't free.

---

## Key Takeaways

1. **EKS control plane is the largest fixed cost** ($73/mo) — unavoidable, no
   optimizations possible. This is the "tax" for managed Kubernetes.

2. **NAT Gateway is surprisingly expensive** — $33-99/mo depending on HA config.
   For dev, a single NAT GW is the biggest easy win.

3. **Spot instances save real money** — Karpenter's Spot + On-Demand mix saves
   ~$50/mo on workload nodes in dev.

4. **Platform overhead is ~$57/mo** — Prometheus, Grafana, Loki, ArgoCD, Kyverno,
   etc. consume 1.5 nodes. This is the cost of observability and security — but
   the alternative (no monitoring, no policy) is much more expensive in incidents.

5. **Biggest future savings: Reserved Instances + Graviton** — 1-year RI on the
   managed node group + Graviton (ARM) could save $80-100/mo combined.

---

## References

- [AWS Pricing Calculator](https://calculator.aws/)
- [EKS pricing](https://aws.amazon.com/eks/pricing/)
- [EC2 ap-south-1 pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [RDS PostgreSQL pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [ElastiCache pricing](https://aws.amazon.com/elasticache/pricing/)
- Grafana Cost Dashboard: `observability/grafana/dashboards/cost-dashboard.json`
