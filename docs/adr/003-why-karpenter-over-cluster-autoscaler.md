# ADR-003: Use Karpenter over Cluster Autoscaler for Node Autoscaling

**Date:** 2026-03-25
**Status:** Accepted

---

## Context

As pod count grows — from load spikes, new deployments, or HPA scaling — the cluster needs
to provision new nodes automatically. Conversely, during low traffic, unused nodes should
be removed to avoid paying for idle EC2 capacity.

Two mature solutions exist for EKS:

1. **Cluster Autoscaler (CAS)** — the original Kubernetes node autoscaler, backed by AWS
   Auto Scaling Groups (ASGs)
2. **Karpenter** — AWS's next-generation node provisioner, open-sourced in 2021 and donated
   to CNCF in 2023

We need to choose one as the primary node scaling mechanism for this cluster.

---

## Decision

We will use **Karpenter** as the primary node provisioner.

The managed node group created in the EKS Terraform module (Task 11) remains as a
**bootstrap floor** — it ensures at least 2 nodes exist before Karpenter is installed.
Once Karpenter is running, it takes over new node provisioning.

---

## Options Considered

### Option A: Cluster Autoscaler (CAS)

CAS scales AWS Auto Scaling Groups based on pending pod counts. It has been the standard
EKS scaling solution since 2018.

**Pros:**
- Mature, battle-tested — runs in production at massive scale
- Deep documentation and community knowledge
- Works with any Kubernetes distribution (not just EKS)
- Native ASG integration — familiar to AWS operations teams

**Cons:**
- Slow: scale-out takes 3-5 minutes (ASG launch + node join + pod schedule)
- Rigid instance types: ASG is configured for one or a few instance types; if that type
  is unavailable in an AZ, pods stay pending
- Over-provisioning: CAS can't bin-pack well — it often provisions a full node when
  only a fraction is needed
- Scale-in is conservative: CAS waits for a long idle period before terminating nodes
  to avoid thrashing, which means paying for empty nodes longer than necessary
- Requires managing ASG Launch Templates — more operational overhead
- No support for Spot diversity: managing multiple Spot ASGs (for price diversification)
  requires complex configurations

### Option B: Karpenter

Karpenter directly calls EC2 Fleet APIs to launch nodes, bypassing ASGs entirely.
It evaluates all pending pods together, selects the optimal instance type, and launches
a node in approximately 60 seconds.

**Pros:**
- **Fast**: 60-90 seconds from pending pod to running pod (vs 3-5 minutes with CAS)
- **Instance flexibility**: NodePool defines constraints (vCPU, memory, arch); Karpenter
  picks the cheapest available instance that fits — automatically handles AZ capacity issues
- **Bin-packing**: evaluates all pending pods at once and consolidates onto the fewest nodes
- **Consolidation**: actively moves pods to reclaim partially-used nodes, reducing waste
- **Spot + On-Demand mix**: a single NodePool can launch Spot or On-Demand based on
  interruption tolerance — no separate ASG management
- **Native EKS integration**: AWS maintains Karpenter; deep integration with EKS APIs
- **CNCF project**: vendor-neutral governance, growing ecosystem

**Cons:**
- Younger project: fewer years of large-scale production data than CAS (though AWS
  uses it internally at massive scale)
- EKS-optimized: while a cloud-provider-agnostic version exists, Karpenter's strengths
  are AWS-specific — not portable to GKE/AKS without additional work
- More concepts to understand: NodePool, EC2NodeClass, Consolidation policy vs CAS's
  simpler ASG-based model
- Requires IRSA permissions to call EC2 APIs directly (more IAM surface area)

---

## Rationale

**Karpenter wins on the metrics that matter for this workload:**

1. **Scale-out speed**: an e-commerce platform has spiky traffic — flash sales, marketing
   events, viral moments. A 3-5 minute scale-out means users hit errors during the spike.
   Karpenter's 60-90 second provisioning means the HPA scales pods, Karpenter launches
   nodes, and new pods start — all within 2 minutes of a traffic spike.

2. **Cost efficiency**: Karpenter's consolidation actively reclaims wasted capacity.
   In practice, teams report 20-40% compute cost reduction vs CAS after switching.
   For a portfolio project this demonstrates cost-awareness; for a real product this
   is direct P&L impact.

3. **Spot diversity**: the order-worker and storefront can tolerate interruptions.
   A single Karpenter NodePool with `karpenter.sh/capacity-type: spot` will launch
   Spot instances across any available type/AZ combination, dramatically reducing the
   chance of simultaneous interruption. CAS requires a separate ASG per Spot type.

4. **Portfolio signal**: Karpenter is the direction AWS is pushing EKS. Senior DevOps
   roles at AWS-heavy companies increasingly expect Karpenter knowledge over CAS.
   Demonstrating it here shows awareness of current best practices.

5. **Simpler long-term**: replacing 3-5 ASGs (one per instance type for diversity) with
   a single NodePool + EC2NodeClass is less operational surface area, not more.

**Why keep the managed node group at all?**
Karpenter runs as a pod on the cluster — it can't provision the node it needs to run on.
The managed node group (2x t3.medium) provides the bootstrap floor: system pods
(CoreDNS, kube-proxy, vpc-cni, Karpenter itself) run on these nodes. Karpenter handles
all application workload scaling.

---

## Consequences

### Positive
- Sub-2-minute scale-out for traffic spikes
- Automatic bin-packing reduces idle node cost
- Spot instance diversity reduces interruption risk
- Single NodePool replaces multiple ASGs — less config to maintain
- Active consolidation reclaims partially-used nodes automatically

### Negative
- Karpenter pod is a single point of failure for scaling (mitigated: 2 replicas + PodDisruptionBudget)
- Direct EC2 API access requires broader IRSA permissions than CAS's ASG-scoped permissions
- If a NodePool is misconfigured, pods stay pending with no useful error message

### Risks
- **Spot interruption**: if cluster runs on 100% Spot and AWS reclaims many instances
  simultaneously, pods may not reschedule fast enough.
  *Mitigation*: NodePool prioritizes Spot but falls back to On-Demand for critical workloads
  (product-api). Order-worker and storefront can use pure Spot.

- **Runaway scaling**: a misconfigured HPA + Karpenter could provision expensive nodes
  endlessly.
  *Mitigation*: NodePool sets `limits: cpu: 100` and `memory: 400Gi` — hard ceiling
  on what Karpenter can provision.

- **Node termination during consolidation**: Karpenter may drain and terminate nodes
  while pods are running.
  *Mitigation*: PodDisruptionBudgets on all services ensure at least 1 replica stays
  available during consolidation (see Task 17).

---

## Implementation Notes

```
kubernetes/platform/karpenter/
├── nodepool.yaml       # Defines constraints: instance families, AZs, capacity types
└── ec2nodeclass.yaml   # Defines AMI, subnet tags, security groups, node IAM role
```

**Key NodePool configuration:**
```yaml
spec:
  limits:
    cpu: 100         # Hard ceiling — Karpenter won't exceed this
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s   # Aggressive reclamation — fine for dev
```

**Karpenter IRSA permissions** (added to IAM module in Task 14):
- `ec2:RunInstances`, `ec2:TerminateInstances`
- `ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`
- `ec2:CreateLaunchTemplate`, `ec2:CreateFleet`
- `iam:PassRole` (to pass the node role to new instances)

---

## References

- [Karpenter documentation](https://karpenter.sh/docs/)
- [Karpenter vs Cluster Autoscaler — AWS blog](https://aws.amazon.com/blogs/containers/amazon-eks-now-supports-karpenter/)
- [CNCF Karpenter project page](https://www.cncf.io/projects/karpenter/)
- [Karpenter NodePool reference](https://karpenter.sh/docs/concepts/nodepools/)
- [Karpenter configuration](kubernetes/platform/karpenter/) — Task 22
