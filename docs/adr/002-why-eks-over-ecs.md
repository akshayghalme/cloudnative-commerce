# ADR-002: Use EKS over ECS for Container Orchestration

**Date:** 2026-03-25
**Status:** Accepted

---

## Context

We need a container orchestration platform to run three services (product-api, storefront,
order-worker) on AWS. The platform must:

- Support independent scaling of each service
- Enable zero-downtime deployments
- Integrate with GitOps tooling (ArgoCD)
- Support policy enforcement (image signing verification, resource limits)
- Provide a foundation for chaos engineering experiments
- Demonstrate production-grade patterns for portfolio purposes

The two primary AWS-native options are **ECS (Elastic Container Service)** and
**EKS (Elastic Kubernetes Service)**. A third option — self-managed Kubernetes on EC2 —
was considered and eliminated early.

---

## Decision

We will use **Amazon EKS** with managed node groups.

---

## Options Considered

### Option A: Amazon ECS (Fargate + EC2 launch types)

ECS is AWS's proprietary container orchestration service. Fargate removes node management
entirely; EC2 launch type gives more control over the underlying instances.

**Pros:**
- Significantly simpler to get started — no control plane to manage
- Fargate eliminates node patching, AMI updates, and capacity planning
- Deep native AWS integration (IAM task roles, CloudWatch, ALB target groups)
- Lower operational overhead for small teams
- Cheaper at small scale (no EKS control plane fee of $0.10/hr)
- Service Connect simplifies service-to-service communication

**Cons:**
- Proprietary — skills don't transfer outside AWS ecosystem
- No Kubernetes ecosystem: no Helm, no ArgoCD, no Kyverno, no Karpenter
- GitOps story is weaker — CodePipeline/CodeDeploy vs ArgoCD
- No native policy engine (Kyverno/OPA) for admission control
- Limited chaos engineering tooling (Litmus, ChaosMesh don't support ECS)
- No horizontal pod autoscaler; scaling targets are service-level only
- Cannot demonstrate Kubernetes expertise, which is the #1 DevOps hiring signal

### Option B: Amazon EKS (Managed Node Groups)

EKS runs an AWS-managed Kubernetes control plane. Managed node groups handle node
provisioning, AMI patching, and draining automatically.

**Pros:**
- Kubernetes is the industry standard — skills transfer across AWS, GCP, Azure, on-prem
- Full ecosystem access: Helm, ArgoCD, Kyverno, Karpenter, Prometheus, Litmus
- GitOps-native: ArgoCD was built for Kubernetes
- Fine-grained admission control via Kyverno policies
- HPA + Karpenter = sophisticated autoscaling (scale pods → scale nodes automatically)
- Chaos engineering first-class support (Litmus, ChaosMesh both Kubernetes-native)
- IRSA (IAM Roles for Service Accounts) — pod-level IAM without node-level credentials
- Hiring managers specifically look for EKS/Kubernetes experience

**Cons:**
- Higher operational complexity — more moving parts
- Control plane cost: $0.10/hr (~$72/month) even when idle
- Requires understanding of Kubernetes primitives (pods, deployments, services, ingress)
- Node group management adds surface area vs Fargate
- Steeper learning curve for teams new to Kubernetes

### Option C: Self-managed Kubernetes on EC2

Run `kubeadm` or `kops` to manage the entire Kubernetes stack on EC2 instances.

**Pros:**
- Maximum control over every component
- Can run older Kubernetes versions if needed

**Cons:**
- Enormous operational burden — etcd backups, control plane HA, certificate rotation
- No justification for this overhead when EKS manages the control plane
- Eliminated immediately — never appropriate for a small team without dedicated platform engineers

---

## Rationale

**EKS wins on every axis that matters for this project:**

1. **Portfolio signal**: Kubernetes is the single most in-demand DevOps skill. ECS experience
   doesn't appear in the majority of senior DevOps job postings; Kubernetes/EKS appears in
   almost all of them. This project exists to demonstrate production-grade skills — ECS would
   undermine that goal.

2. **Ecosystem lock-in**: ECS traps skills inside AWS. EKS knowledge transfers directly to
   GKE, AKS, and on-prem clusters. A Helm chart works everywhere; an ECS task definition
   works nowhere else.

3. **GitOps**: ArgoCD is purpose-built for Kubernetes. It provides real-time diff, automated
   sync, and rollback capabilities that have no equivalent in the ECS world. GitOps is a core
   project requirement.

4. **Policy enforcement**: Kyverno admission webhooks let us enforce image signing, resource
   limits, and registry restrictions at the cluster level. ECS has no equivalent.

5. **Chaos engineering**: Litmus Chaos (our chosen chaos tool — see ADR-005) requires
   Kubernetes. ECS chaos engineering is significantly more limited.

6. **Cost trade-off is acceptable**: The $72/month EKS control plane fee is worth it for
   the ecosystem access. We offset this with a single NAT Gateway in dev (saves $64/month)
   and Karpenter's bin-packing (reduces wasted node capacity).

**Why not ECS Fargate for simplicity?**
Simplicity is not a goal here. This is a portfolio project designed to demonstrate operational
sophistication. A hiring manager reviewing ECS + CodePipeline will see a junior setup.
A hiring manager reviewing EKS + ArgoCD + Kyverno + Karpenter will see a senior engineer.

---

## Consequences

### Positive
- Access to the full Kubernetes ecosystem (Helm, ArgoCD, Kyverno, Karpenter, Prometheus, Litmus)
- Portable skills — this knowledge transfers to any cloud or on-prem environment
- GitOps via ArgoCD with real sync status, drift detection, and one-click rollback
- Pod-level IAM via IRSA — no shared node credentials, least-privilege per service
- Sophisticated autoscaling: HPA scales pods → Karpenter scales nodes in response
- Strong portfolio signal for $150K+ DevOps roles

### Negative
- $72/month control plane cost in dev environment (always-on)
- More concepts to understand before anything runs (VPC CNI, OIDC provider, node groups)
- Debugging requires `kubectl` proficiency — `docker ps` is no longer sufficient

### Risks
- **EKS version upgrades**: Kubernetes releases every 4 months; EKS supports a version for
  ~14 months. Upgrades require managed node group rolling updates — tested in staging first.
  *Mitigation*: Terraform module pins the EKS version; upgrades are explicit PRs.

- **Node group capacity**: If Karpenter is misconfigured, nodes may not provision and pods
  stay pending.
  *Mitigation*: Karpenter NodePool has explicit instance type fallbacks (see ADR-003).

- **etcd data loss**: EKS manages etcd but a misconfigured `kubectl delete` could remove
  critical resources.
  *Mitigation*: Velero backups scheduled daily (added in Phase 5).

---

## Implementation Notes

```
terraform/modules/eks/
├── main.tf          # EKS cluster, managed node group, OIDC provider
├── variables.tf     # cluster_name, k8s_version, node_instance_types, etc.
└── outputs.tf       # cluster_endpoint, cluster_ca, oidc_provider_arn

kubernetes/platform/
├── karpenter/       # NodePool + EC2NodeClass (replaces managed node group for scale)
├── kyverno/         # Admission policies
└── cert-manager/    # TLS for ingress
```

**Key configuration decisions:**
- Kubernetes version: `1.30` (latest stable at project start, pinned in Terraform)
- Node instance type: `t3.medium` for dev (2 vCPU, 4GB) — sufficient for 3 small services
- Managed node group min/max: `1/3` in dev, `2/6` in prod
- OIDC provider: enabled from day 1 — required for IRSA (pod-level IAM)
- EKS add-ons managed by Terraform: `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`

---

## References

- [EKS vs ECS — AWS documentation comparison](https://docs.aws.amazon.com/decision-guides/latest/containers-on-aws-how-to-choose/choosing-aws-container-service.html)
- [CNCF Survey 2023 — Kubernetes adoption at 84% of container users](https://www.cncf.io/reports/cncf-annual-survey-2023/)
- [IRSA — IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Karpenter vs Cluster Autoscaler](docs/adr/003-why-karpenter-over-cluster-autoscaler.md) — ADR-003
- [ArgoCD vs Flux](docs/adr/004-why-argocd-over-flux.md) — ADR-004
