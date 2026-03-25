# CloudNative Commerce — Platform Infrastructure

Production infrastructure for a microservices e-commerce platform running on AWS.
Manages the full lifecycle from provisioning to observability to chaos resilience.

## Architecture

![Architecture](docs/architecture-diagram.png)

**Stack:**

| Layer | Tools |
|-------|-------|
| Application | Go, React/Next.js, Python, PostgreSQL, Redis |
| Container Orchestration | EKS, Karpenter, Kyverno |
| GitOps | ArgoCD, Kustomize |
| Infrastructure as Code | Terraform, Terragrunt |
| CI/CD + Supply Chain Security | GitHub Actions, Trivy, Cosign, SBOM |
| Observability | Prometheus, Grafana, Loki, OpenTelemetry |
| Chaos + Load Testing | Litmus Chaos, k6 |

## Services

| Service | Language | Description |
|---------|----------|-------------|
| `product-api` | Go | REST API — products, inventory, orders |
| `storefront` | React/Next.js | Customer-facing SPA |
| `order-worker` | Python | Async order processing via SQS |

## Infrastructure Overview

- **AWS region:** ap-south-1 (Mumbai), 3 AZs
- **Networking:** VPC with public/private subnet split — ALB in public, EKS nodes + RDS + Redis in private
- **EKS:** Managed node groups, IRSA for pod-level IAM, Karpenter for node autoscaling
- **Data:** RDS PostgreSQL (Multi-AZ), ElastiCache Redis, automated backups
- **Ingress:** ALB via ingress-nginx, TLS via cert-manager + ACM
- **Secrets:** External Secrets Operator pulling from AWS Secrets Manager
- **Image security:** All images scanned (Trivy), signed (Cosign), SBOM generated (Syft)

## Environments

| Environment | Purpose | Auto-deploy |
|-------------|---------|-------------|
| `dev` | Development, integration testing | Yes — on merge to `main` |
| `staging` | Pre-prod validation, load testing | Yes — after dev passes |
| `prod` | Production | Manual approval gate |

## Progress

| Layer | Status |
|-------|--------|
| Application (Go, React, Python) | :green_circle: Complete |
| Infrastructure as Code (Terraform, Terragrunt) | :green_circle: Complete |
| Kubernetes + GitOps (EKS, ArgoCD, Kustomize) | :green_circle: Complete |
| CI/CD + Supply Chain Security | :green_circle: Complete |
| Observability (Prometheus, Grafana, Loki, OTel) | :green_circle: Complete |
| Chaos + Reliability (Litmus, k6) | :green_circle: Complete |

## Observability Stack

**Metrics → Logs → Traces** — all accessible in a single Grafana instance.

| Component | Tool | Purpose |
|-----------|------|---------|
| Metrics | Prometheus + kube-prometheus-stack | Cluster + application metrics, 15d retention |
| Dashboards | Grafana | Golden signals, cluster health, cost/efficiency |
| Logging | Loki + Promtail | Label-indexed log aggregation, 14d retention |
| Tracing | OpenTelemetry Collector + Tempo | Distributed traces with tail-based sampling |
| Alerting | Alertmanager | Severity-based routing to PagerDuty + Slack |

### Grafana Dashboards

| Dashboard | What it shows |
|-----------|--------------|
| **Golden Signals** | Request rate, error rate, P50/P95/P99 latency, CPU/memory saturation per service |
| **Cluster Health** | Node readiness, pod count/restarts, CPU/memory/disk per node, deployment availability |
| **Cost & Efficiency** | Resource utilization efficiency, requested vs actual, over-provisioned container detection |

### SLO-Based Alerting (Google SRE Model)

Alerts fire based on **error budget burn rate**, not raw thresholds:

| Burn Rate | Time to Budget Exhaustion | Severity | Action |
|-----------|--------------------------|----------|--------|
| 14.4x | ~2 days | Critical | Page on-call immediately |
| 6x | ~5 days | Warning | Investigate within hours |
| 3x | ~10 days | Info | Investigate this week |

## Cost

Estimated monthly AWS cost: **~$238/mo** (dev) | **~$470/mo** (prod)

[Full cost analysis with optimization strategies](docs/cost-analysis.md)

| Top costs (dev) | Monthly | Optimization |
|-----------------|---------|-------------|
| EKS control plane | $73 | Fixed — unavoidable |
| EC2 nodes | $73 | Spot instances save ~$50/mo |
| NAT Gateway | $33 | Single AZ (saves $65 vs HA) |
| Platform overhead | $57 | Cost of production-grade ops |

## Runbooks

- [Scale-up procedure](docs/runbooks/scale-up.md)
- [DB failover](docs/runbooks/db-failover.md)
- [Incident response](docs/runbooks/incident-response.md)

## Architecture Decision Records

| # | Decision |
|---|----------|
| [ADR-001](docs/adr/001-vpc-architecture.md) | VPC layout — 3-AZ public/private split |
| [ADR-002](docs/adr/002-why-eks-over-ecs.md) | EKS over ECS |
| [ADR-003](docs/adr/003-why-karpenter-over-cluster-autoscaler.md) | Karpenter over Cluster Autoscaler |
| [ADR-004](docs/adr/004-why-argocd-over-flux.md) | ArgoCD over Flux |
| [ADR-005](docs/adr/005-why-kyverno-over-opa-gatekeeper.md) | Kyverno over OPA/Gatekeeper |
| [ADR-006](docs/adr/006-why-loki-over-elk.md) | Loki over ELK |

## SLOs

| Service | Availability | Latency (p99) |
|---------|-------------|----------------|
| product-api | 99.9% | < 200ms |
| storefront | 99.5% | < 1s |
| order-worker | 99.9% (processing) | < 30s end-to-end |

## Chaos Engineering

| Experiment | Hypothesis | Probes | Report |
|-----------|-----------|--------|--------|
| [Pod kill](chaos/experiments/pod-kill-product-api.yaml) | HPA recovers < 30s, zero errors | HTTP health, Prometheus SLO, min pods | [Game Day #001](chaos/game-days/001-pod-kill-report.md) |
| [Node drain](chaos/experiments/node-drain.yaml) | Karpenter replaces < 2min, PDB respected | HTTP health (both services), SLO, node count | [Game Day #002](chaos/game-days/002-node-drain-report.md) |
| [Network partition](chaos/experiments/network-partition.yaml) | Graceful degradation, auto-recovery | Pod survival, healthz independence, post-chaos recovery | — |

### Load Testing (k6)

| Test | Pattern | Thresholds |
|------|---------|-----------|
| [API throughput](chaos/load-tests/k6-product-api.js) | 10 → 100 → 200 VUs, staged ramp | P95 < 300ms, P99 < 500ms, errors < 1% |
| [Order flow](chaos/load-tests/k6-order-flow.js) | 10 orders/s steady + 50 orders/s flash sale | E2E P95 < 2s, order creation P95 < 500ms |

## Local Development

```bash
# Prerequisites: Docker, docker-compose
git clone https://github.com/akshayghalme/cloudnative-commerce.git
cd cloudnative-commerce
cp .env.example .env
make compose-up
```

## Deploying to AWS

```bash
# Prerequisites: AWS CLI (configured), Terraform >= 1.7, kubectl, Helm, gh CLI

# 1. Provision infrastructure
cd terraform/environments/dev
terraform init && terraform apply

# 2. Deploy platform components (cert-manager, ingress, external-secrets)
kubectl apply -f kubernetes/platform/

# 3. Bootstrap ArgoCD — it takes over from here
kubectl apply -f kubernetes/argocd/apps/
```

## Repository Layout

```
cloudnative-commerce/
├── services/           # Application source (Go, React, Python)
├── terraform/          # Modules + environment configs
├── kubernetes/         # Base manifests, Kustomize overlays, ArgoCD apps
├── .github/workflows/  # CI/CD pipelines
├── observability/      # Prometheus rules, Grafana dashboards, Loki, OTel
├── chaos/              # Litmus experiments, k6 load tests, game day reports
└── docs/               # ADRs, runbooks, failure reports, cost analysis
```

## What I Learned

### The hard parts nobody warns you about

**Kubernetes YAML is the easy part. The hard part is the decisions between the YAML.**
Choosing between ArgoCD and Flux, Kyverno and OPA, Loki and ELK — these choices
shape your operational experience for years. I documented every decision as an ADR
because "we use ArgoCD" is not useful without "here's why, and here's what we gave up."

**Platform overhead is real.** Prometheus, Grafana, Loki, ArgoCD, Kyverno, cert-manager,
external-secrets, ingress-nginx, Karpenter — these "free" open-source tools consume
~3.2 vCPU and 5 GiB of memory. That's 1.5 t3.medium nodes ($57/mo) just for
infrastructure. Production-grade is not free, even when the software is.

**Security is a supply chain problem.** Image scanning (Trivy) catches known CVEs.
Image signing (Cosign) proves who built it. SBOM generation (Syft) proves what's inside.
Kyverno verification ensures only signed images deploy. Each tool covers one gap —
skip any one and you have a hole.

### What surprised me

**NAT Gateway costs more than the database.** A single NAT Gateway is $33/mo. HA
(three, one per AZ) is $99/mo. The RDS instance is $15/mo. Network egress pricing
is the silent budget killer in AWS.

**SLO-based alerting is a paradigm shift.** Traditional alerts ("error rate > 1%")
fire on transient spikes and cause alert fatigue. Burn-rate alerts ("at this rate,
we'll exhaust our error budget in 2 days") only fire when there's a real problem
worth waking someone up for. Multi-window confirmation eliminates nearly all false
positives.

**Chaos engineering reveals what monitoring misses.** Our network partition experiment
tests something no dashboard can show: "does the application crash when the database
is unreachable, or does it degrade gracefully?" You can't answer that by looking at
Grafana — you have to break things intentionally.

### What I'd do differently

**Start with the CI/CD pipeline earlier.** I built all the infrastructure before
the pipelines. In a real project, I'd set up the CI pipeline in week 1 — even if
it only runs `terraform fmt` and `docker build`. Feedback loops compound.

**Use Helm for everything or Kustomize for everything, not both.** Platform
components use Helm values files. Application manifests use Kustomize overlays.
This works, but it means two deployment patterns to understand. Next time, I'd
pick one and commit.

**Add PgBouncer from day one.** Connection pool exhaustion is the most common
database failure mode for Kubernetes workloads. Each pod opens its own pool,
and with HPA scaling pods up/down, the connection count fluctuates wildly.
A PgBouncer sidecar or standalone proxy should be part of the base architecture.
