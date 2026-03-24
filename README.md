# ☁️ CloudNative Commerce

> Production-grade DevOps portfolio project: deploying a microservices e-commerce platform
> on AWS using **Terraform, EKS, ArgoCD, GitHub Actions, Prometheus, and Chaos Engineering**.
>
> Every architectural decision is documented. Every failure is documented. This isn't a tutorial — it's how I'd actually build and operate a production system.

## 🏗️ Architecture

<!-- Add architecture diagram here — update as each layer is built -->

![Architecture](docs/architecture-diagram.png)

**6 Infrastructure Layers:**

| Layer | Tools | Status |
|-------|-------|--------|
| Application | Go, React, Python, PostgreSQL, Redis | 🔴 Not started |
| Kubernetes + GitOps | EKS, ArgoCD, Karpenter, Kyverno | 🔴 Not started |
| Infrastructure as Code | Terraform, Terragrunt, AWS | 🔴 Not started |
| CI/CD + Security | GitHub Actions, Trivy, Cosign, SBOM | 🔴 Not started |
| Observability | Prometheus, Grafana, Loki, OpenTelemetry | 🔴 Not started |
| Chaos + Reliability | Litmus Chaos, k6, Game Days | 🔴 Not started |

## 📐 Key Decisions (ADRs)

| # | Decision | Summary |
|---|----------|---------|
| 001 | [VPC Architecture](docs/adr/001-vpc-architecture.md) | 3-AZ, public/private split, single NAT for dev |
| ... | More ADRs added as project progresses | |

## 💰 Cost Analysis

Estimated AWS cost for dev environment: **~$147/month**
[Full breakdown →](docs/cost-analysis.md)

## 🔥 Chaos Engineering Results

| Experiment | Expected | Actual | Report |
|-----------|----------|--------|--------|
| Pod kill (API) | HPA recovers <30s | 🔴 Pending | — |
| Node drain | Karpenter replaces <2min | 🔴 Pending | — |

## 📊 Observability

<!-- Add Grafana dashboard screenshots as they're built -->

## 🚀 Quick Start

```bash
# Prerequisites: AWS CLI, Terraform, kubectl, Helm, gh CLI
git clone https://github.com/akshayghalme/cloudnative-commerce.git
cd cloudnative-commerce

# Deploy dev environment
cd terraform/environments/dev
terraform init && terraform apply

# Deploy apps via ArgoCD
kubectl apply -f kubernetes/argocd/apps/
```

## 📁 Project Structure

```
cloudnative-commerce/
├── services/          # Application code (Go API, React frontend, Python worker)
├── terraform/         # Infrastructure as Code (modules + environments)
├── kubernetes/        # K8s manifests, ArgoCD apps, Kustomize overlays
├── .github/workflows/ # CI/CD pipelines
├── observability/     # Prometheus, Grafana, Loki, OpenTelemetry configs
├── chaos/             # Litmus experiments, k6 load tests, game day reports
└── docs/              # ADRs, failure reports, runbooks, cost analysis
```

## 📝 What I Learned

*This section is updated as the project evolves. Honest reflections on what was harder than expected, what surprised me, and what I'd do differently.*
