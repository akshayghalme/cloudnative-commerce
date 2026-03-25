# Runbook: Scale-Up Procedure

**Last updated:** 2026-03-25
**Owner:** Platform team
**Severity trigger:** Warning — CPU/memory saturation > 80% sustained

---

## When to Use

- HPA has scaled pods to maxReplicas and latency is still increasing
- Karpenter has hit the NodePool CPU/memory limit (32 CPU / 64 GiB)
- A known traffic event is approaching (sale, launch, marketing campaign)
- Alert: `ProductAPIHighLatency` or cluster CPU gauge > 80%

## Diagnosis

```bash
# 1. Check current pod count vs HPA limits
kubectl get hpa -n commerce

# 2. Check node capacity
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# 3. Check Karpenter limits
kubectl get nodepools -o yaml | grep -A 3 "limits"

# 4. Check pending pods (can't be scheduled)
kubectl get pods -n commerce --field-selector=status.phase=Pending

# 5. Grafana: Cluster Health dashboard → CPU/Memory gauges
# 6. Grafana: Cost dashboard → requested vs actual
```

## Procedure

### Option A: Scale application pods (fast — minutes)

```bash
# Increase HPA maxReplicas for the affected service
kubectl patch hpa product-api -n commerce \
  --type merge -p '{"spec":{"maxReplicas": 15}}'

# Or scale the deployment directly (temporary — HPA will take over)
kubectl scale deployment product-api -n commerce --replicas=8

# Verify pods are running
kubectl get pods -n commerce -l app.kubernetes.io/name=product-api -w
```

**Make it permanent:** update the Kustomize overlay and commit.
```bash
# Edit kubernetes/overlays/<env>/product-api/kustomization.yaml
# Update HPA maxReplicas patch, then commit + push
# ArgoCD will sync the change
```

### Option B: Increase Karpenter node capacity (medium — 5-10 minutes)

```bash
# Check current limits
kubectl get nodepool default -o jsonpath='{.spec.limits}'

# Patch NodePool to increase limits
kubectl patch nodepool default --type merge -p '{
  "spec": {
    "limits": {
      "cpu": "64",
      "memory": "128Gi"
    }
  }
}'

# Watch Karpenter provision new nodes
kubectl get nodes -w
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

**Make it permanent:** update `kubernetes/platform/karpenter/nodepool.yaml`.

### Option C: Add larger instance types (slow — requires node rotation)

Edit the NodePool to allow larger instances:
```yaml
# In kubernetes/platform/karpenter/nodepool.yaml
- key: karpenter.k8s.aws/instance-size
  operator: In
  values: ["small", "medium", "large", "xlarge", "2xlarge"]  # Add 2xlarge
```

## Verification

```bash
# Pods are running and healthy
kubectl get pods -n commerce -l app.kubernetes.io/name=product-api

# HPA is no longer at maxReplicas
kubectl get hpa -n commerce

# Latency has returned to normal
# Grafana: Golden Signals → P99 latency

# No pending pods
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

## Rollback

After the traffic event ends:
```bash
# Reduce HPA maxReplicas back to normal
kubectl patch hpa product-api -n commerce \
  --type merge -p '{"spec":{"maxReplicas": 10}}'

# Karpenter will consolidate underutilized nodes automatically
# (consolidationPolicy: WhenEmptyOrUnderutilized)
```

## Escalation

If scaling doesn't resolve latency:
1. Check database: `kubectl logs` for connection pool exhaustion
2. Check Redis: `redis-cli info` for memory/connection limits
3. Check RDS: CloudWatch → DatabaseConnections, CPUUtilization
4. Page on-call if P99 > 1s for more than 10 minutes
