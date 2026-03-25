# ADR-004: Use ArgoCD over Flux for GitOps

**Date:** 2026-03-25
**Status:** Accepted

---

## Context

With Kubernetes manifests and Kustomize overlays in place, we need a GitOps
controller to watch the repository and reconcile cluster state with Git.
The two leading CNCF-graduated GitOps tools for Kubernetes are ArgoCD and Flux v2.

Both implement the core GitOps contract: Git is the source of truth, and the
controller continuously reconciles the cluster toward the desired state defined in Git.
The choice between them is not about correctness — both are production-grade — but
about operator experience, team fit, and specific capabilities.

---

## Decision

We will use **ArgoCD**.

---

## Options Considered

### Option A: ArgoCD

ArgoCD is a declarative GitOps controller with a rich UI and a strong focus on
application-centric deployment workflows.

**Pros:**
- **UI**: ArgoCD's web UI is genuinely useful — real-time application health,
  resource tree visualization, sync history, diff viewer, and one-click rollback.
  This is not just a nice-to-have; it dramatically reduces time-to-diagnose during
  incidents.
- **ApplicationSet**: generates Applications dynamically from templates + generators
  (matrix, git directory, cluster list). Adding a new environment is one list entry.
- **AppProject**: fine-grained RBAC at the project level — scope which repos,
  namespaces, and resource types a project can touch.
- **Multi-cluster**: single ArgoCD instance can deploy to many clusters via registered
  destinations — useful when staging and prod are separate clusters.
- **Manual sync gate for prod**: `automated.prune: false` on prod Applications gives
  a human approval step without needing a separate pipeline.
- **Adoption**: larger enterprise adoption, more job postings reference ArgoCD by name.

**Cons:**
- Heavier: ArgoCD itself runs ~5 pods (server, repo-server, application-controller,
  dex, redis) vs Flux's ~3 controllers
- ArgoCD server is a single point of failure for the UI (controllers continue to
  reconcile if the server is down)
- More opinionated: ApplicationSet and AppProject are ArgoCD-specific abstractions

### Option B: Flux v2

Flux v2 is a set of composable GitOps controllers (source-controller, kustomize-controller,
helm-controller, notification-controller) that follow the Kubernetes operator pattern.

**Pros:**
- **Lightweight**: ~3 controllers, lower resource footprint
- **Composable**: each controller is a separate CRD — use only what you need
- **Operator-native**: Flux CRDs (GitRepository, Kustomization, HelmRelease) feel
  more like native Kubernetes objects than ArgoCD's Application CRD
- **OCI support**: Flux can pull manifests from OCI registries, not just Git — useful
  for distributing Helm charts as container images
- **Notification controller**: fine-grained alerting (per-object events to Slack,
  PagerDuty, Teams) without external dependencies
- **Better Helm story**: HelmRelease CRD is more powerful than ArgoCD's Helm source

**Cons:**
- No built-in UI — requires Weave GitOps or a third-party dashboard
- ApplicationSet equivalent (Flux's `Kustomization` with generators) is less
  feature-rich and less documented
- Manual sync gate requires notification + external pipeline integration — more work
  to implement approval gates for prod
- Smaller enterprise mindshare: fewer job descriptions mention Flux by name

### Option C: Plain `kubectl apply` in CI

Run `kubectl kustomize | kubectl apply` directly in GitHub Actions, no GitOps controller.

**Pros:** Simple, no additional components

**Cons:**
- No drift detection — manual changes to the cluster persist silently
- No rollback history — you'd have to re-run a previous CI job
- No health checks — CI considers the deploy done when `kubectl apply` returns 0,
  not when pods are actually healthy
- Eliminated immediately — defeats the purpose of having Kustomize overlays

---

## Rationale

**ArgoCD wins primarily on operator experience and portfolio signal:**

1. **The UI matters during incidents**: when `product-api` is degraded at 2am, a
   developer opening the ArgoCD UI sees the exact diff between desired and actual state,
   which pods are failing health checks, and what changed in the last sync. With Flux,
   you're reading controller logs and running `kubectl describe`. Both work — one is
   faster under pressure.

2. **ApplicationSet is uniquely powerful here**: the matrix generator (3 services × 3
   environments = 9 Applications from one manifest) is something Flux cannot replicate
   as cleanly. For this multi-service, multi-environment setup, ApplicationSet pays off
   immediately.

3. **Manual sync gate is simpler**: setting `automated: null` on the prod Application
   gives a one-click human gate in the UI. Flux requires a notification webhook +
   external approval workflow to achieve the same.

4. **Job market signal**: "ArgoCD" appears in significantly more senior DevOps job
   postings than "Flux." This is a portfolio project — demonstrating ArgoCD proficiency
   is more directly valuable.

**Why not Flux?**
Flux is an excellent choice — particularly for teams who prefer pure CLI workflows,
Helm-heavy setups, or OCI-based distribution. If this project used Helm charts
extensively (vs Kustomize), Flux's HelmRelease controller would be the better fit.
The Flux vs ArgoCD decision is genuinely close; the tiebreaker here is the UI value
during incident response and ApplicationSet's fit for our multi-environment layout.

---

## Consequences

### Positive
- Real-time drift detection with UI visualization
- ApplicationSet generates 9 Applications from a single matrix manifest
- AppProject enforces least-privilege: one repo, one namespace, explicit resource types
- prod sync gate keeps automated deploys out of production
- `selfHeal: true` means Git is always authoritative — no silent drift

### Negative
- 5 additional pods running on the cluster (~200m CPU, ~500Mi memory overhead)
- ArgoCD version upgrades require careful coordination (CRD updates, breaking changes)
- Developers need to learn ArgoCD concepts (Application, AppProject, sync waves)

### Risks
- **ArgoCD server outage**: if the ArgoCD server pod crashes, the UI is unavailable.
  Controllers continue reconciling — deployments still work, but you lose visibility.
  *Mitigation*: ArgoCD server has a PDB; alert on pod restarts.

- **Repo-server bottleneck**: with many Applications, the repo-server (which runs
  `kustomize build`) can become a bottleneck.
  *Mitigation*: increase repo-server replicas in the Helm values when Application
  count exceeds ~50.

---

## Implementation Notes

```
kubernetes/argocd/
├── apps/
│   ├── project.yaml          # AppProject: commerce
│   ├── product-api.yaml      # Application: product-api-dev
│   ├── storefront.yaml       # Application: storefront-dev
│   └── order-worker.yaml     # Application: order-worker-dev
└── applicationset.yaml       # ApplicationSet: matrix 3×3
```

**Bootstrap sequence:**
```bash
# 1. Install ArgoCD via Helm (platform components — Task 26)
helm install argocd argo/argo-cd -n argocd -f kubernetes/platform/argocd/values.yaml

# 2. Apply AppProject + ApplicationSet (self-managed from this point)
kubectl apply -f kubernetes/argocd/apps/project.yaml
kubectl apply -f kubernetes/argocd/applicationset.yaml

# 3. ArgoCD syncs itself and all Applications
```

**Helm values for ArgoCD** (in `kubernetes/platform/argocd/values.yaml`):
- `server.replicas: 2` for HA
- `applicationSet.replicaCount: 2`
- OIDC integration with GitHub for SSO (avoids managing ArgoCD users)
- Ingress with cert-manager TLS

---

## References

- [ArgoCD documentation](https://argo-cd.readthedocs.io/)
- [Flux v2 documentation](https://fluxcd.io/flux/)
- [ArgoCD vs Flux — CNCF comparison](https://www.cncf.io/blog/2024/06/10/comparing-argo-cd-and-flux/)
- [ApplicationSet controller docs](https://argocd-applicationset.readthedocs.io/)
- [ArgoCD configuration](kubernetes/argocd/) — Tasks 20, 26
