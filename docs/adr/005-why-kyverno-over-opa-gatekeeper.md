# ADR-005: Use Kyverno over OPA/Gatekeeper for Policy Enforcement

**Date:** 2026-03-25
**Status:** Accepted

---

## Context

With workloads deploying to EKS via ArgoCD, we need an admission controller to
enforce security and operational policies — restricting image registries,
requiring resource limits, blocking privileged containers, and mandating labels.

Kubernetes has no built-in policy engine beyond Pod Security Standards (PSS),
which only covers a narrow set of security controls. For custom policies (e.g.,
"images must come from our ECR account"), we need a dedicated policy engine.

The two leading CNCF options are Kyverno and OPA/Gatekeeper.

---

## Decision

We will use **Kyverno**.

---

## Options Considered

### Option A: Kyverno

Kyverno is a Kubernetes-native policy engine where policies are written as
YAML CRDs — no new language to learn.

**Pros:**
- **Policies are YAML**: a Kyverno ClusterPolicy looks like any other Kubernetes
  manifest. A DevOps engineer who knows `kubectl` can read and write policies
  immediately. No new language to learn.
- **Validate, mutate, and generate**: Kyverno can validate (block/audit),
  mutate (inject defaults like resource limits or labels), and generate
  (auto-create NetworkPolicies when a namespace is created) — all in one tool.
- **Match/exclude granularity**: fine-grained resource matching by kind,
  namespace, labels, annotations, and user/group. Excluding system namespaces
  is one `exclude` block.
- **Built-in image verification**: `verifyImages` rule type natively supports
  Cosign signature verification and Notary — no external webhook needed.
- **Policy reports**: generates PolicyReport CRDs that tools like Policy Reporter
  can visualize. Background scanning catches existing violations, not just new
  admissions.
- **Lower barrier to contribution**: any team member who can write YAML can
  propose a policy change in a PR. No Rego expertise required.

**Cons:**
- Younger project than OPA (CNCF graduated August 2024 vs OPA graduated 2021)
- For extremely complex logic (cross-resource validation, external data
  lookups), YAML-based policies can become verbose
- Fewer third-party integrations than OPA (OPA is used beyond Kubernetes —
  API gateways, Terraform, CI pipelines)

### Option B: OPA/Gatekeeper

Open Policy Agent (OPA) is a general-purpose policy engine. Gatekeeper is the
Kubernetes-specific admission controller that uses OPA under the hood. Policies
are written in Rego, OPA's purpose-built policy language.

**Pros:**
- **Rego is powerful**: a full logic programming language — can express any
  policy, no matter how complex. Cross-resource validation, external data
  fetches, and recursive logic are all possible.
- **General-purpose**: OPA is not Kubernetes-specific. The same Rego policies
  can enforce rules in API gateways (Envoy), Terraform plans (conftest),
  and CI pipelines. One language for all policy.
- **CNCF graduated (2021)**: longer track record, battle-tested at scale by
  Netflix, Goldman Sachs, and others.
- **ConstraintTemplate library**: Gatekeeper has a large library of
  pre-built ConstraintTemplates for common policies.
- **External data**: OPA can query external APIs during evaluation (e.g.,
  check a CMDB for approved service names).

**Cons:**
- **Rego learning curve**: Rego is not YAML, not JSON, not a general-purpose
  language. It's a Datalog derivative that takes meaningful time to learn.
  Most DevOps engineers have never seen it. This is the single biggest
  adoption barrier.
- **Two-layer abstraction**: Gatekeeper requires writing a ConstraintTemplate
  (Rego code) AND a Constraint (parameters). A single policy is two resources,
  not one.
- **No built-in mutation**: Gatekeeper added mutation support in v3.10 but
  it's less mature and less intuitive than Kyverno's mutation rules.
- **No image verification**: verifying container image signatures requires
  a separate tool (e.g., Connaisseur, Ratify) or custom Rego + external data.
- **Kubernetes-only in Gatekeeper form**: while OPA itself is general-purpose,
  the Gatekeeper deployment is Kubernetes-specific. The "write once, use
  everywhere" promise requires maintaining OPA outside Gatekeeper separately.

### Option C: Kubernetes Pod Security Standards (PSS) alone

Use the built-in PodSecurity admission controller with namespace labels
(`pod-security.kubernetes.io/enforce: restricted`).

**Pros:** Zero additional components, built into Kubernetes since 1.25

**Cons:**
- Only covers pod security contexts (privileged, hostNetwork, runAsRoot, etc.)
- Cannot enforce custom policies: image registries, required labels, resource limits
- No audit/report mechanism beyond admission rejection
- Eliminated immediately — does not meet our requirements

---

## Rationale

**Kyverno wins primarily on adoption speed and operational simplicity:**

1. **YAML fluency is a given; Rego fluency is not**: every engineer on this
   project reads and writes YAML daily. Zero engineers have Rego experience.
   With Kyverno, writing a new policy is a 15-minute PR. With OPA/Gatekeeper,
   it's "learn Rego first" — a multi-day investment per person. For a team
   of this size, that overhead is not justified.

2. **One resource, not two**: a Kyverno ClusterPolicy is a single manifest
   that contains the match criteria, the validation logic, and the message.
   A Gatekeeper policy requires a ConstraintTemplate (Rego) + Constraint
   (parameters) — two resources, two files, two review cycles. More moving
   parts for the same outcome.

3. **Image verification is built in**: Task 33 requires verifying Cosign
   signatures on container images. Kyverno's `verifyImages` rule handles this
   natively. With Gatekeeper, we'd need to deploy Ratify or Connaisseur as
   a separate component — more infrastructure to maintain.

4. **Mutation + generation**: Kyverno can inject default labels, add resource
   limits to containers that forgot them, and auto-generate NetworkPolicies
   per namespace. With Gatekeeper, mutation is possible but less mature, and
   generation requires a separate controller.

5. **Policy reports**: Kyverno's background scanning generates PolicyReport
   CRDs showing existing violations — not just blocking new ones. This gives
   visibility into compliance posture without deploying anything extra.

**Why not OPA/Gatekeeper?**
OPA is the right choice when: (a) the team already knows Rego, (b) policies
need to span beyond Kubernetes (Terraform, Envoy, CI), or (c) policies require
complex cross-resource logic that YAML can't express cleanly. None of these
apply here. OPA's generality is a strength at scale but a tax at our size.

If we later need OPA for Terraform policy enforcement (conftest), we can run
OPA for that specific use case alongside Kyverno in-cluster — they solve
different problems at different layers.

---

## Consequences

### Positive
- New policies are YAML PRs — any team member can contribute
- Image signature verification (Task 33) needs no additional components
- Background scanning catches pre-existing violations
- Mutation rules can inject missing labels/limits as a safety net
- PolicyReport CRDs provide compliance dashboards

### Negative
- Extremely complex policies (cross-resource, external data) may hit YAML
  expressiveness limits — would require CEL expressions or JMESPath
- OPA/Rego skills are more transferable to non-Kubernetes contexts
- If the team later adopts OPA for Terraform/Envoy, they'll have two policy
  systems to maintain

### Risks
- **Kyverno controller outage**: if Kyverno pods are down, the webhook fails
  open by default — pods deploy without policy checks.
  *Mitigation*: configure `failurePolicy: Fail` on critical policies (registry
  restriction, privileged) so admission is denied when Kyverno is unavailable.
  Set PDB to keep at least 2 replicas running.

- **Policy too strict for system components**: an overly broad policy can
  block kube-system or ArgoCD pods.
  *Mitigation*: all policies exclude system namespaces (kube-system, kyverno,
  argocd, karpenter). Start operational policies in Audit mode, switch to
  Enforce after validation.

---

## Implementation Notes

```
kubernetes/platform/kyverno/
├── require-labels.yaml           # Audit: app, environment, managed-by
├── restrict-registries.yaml      # Enforce: ECR, distroless, Docker official
├── require-resource-limits.yaml  # Audit: CPU/memory requests + limits
├── disallow-privileged.yaml      # Enforce: no privileged, non-root, no escalation
└── kustomization.yaml
```

**Enforcement strategy:**
| Policy | Initial Mode | Target Mode | When to Enforce |
|--------|-------------|-------------|-----------------|
| restrict-registries | Enforce | Enforce | Immediately — no exceptions |
| disallow-privileged | Enforce | Enforce | Immediately — no exceptions |
| require-labels | Audit | Enforce | After all workloads are labeled |
| require-resource-limits | Audit | Enforce | After all workloads have limits |

**Future policies** (referenced in later tasks):
- Task 33: `verifyImages` policy for Cosign signature verification

---

## References

- [Kyverno documentation](https://kyverno.io/docs/)
- [OPA/Gatekeeper documentation](https://open-policy-agent.github.io/gatekeeper/)
- [Kyverno vs OPA/Gatekeeper comparison](https://neonmirrors.net/post/2021-02/kubernetes-policy-comparison-opa-gatekeeper-vs-kyverno/)
- [CNCF policy engines landscape](https://landscape.cncf.io/card-mode?category=security-compliance)
- [Kyverno policies](kubernetes/platform/kyverno/) — Task 23
