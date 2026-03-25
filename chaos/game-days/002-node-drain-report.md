# Game Day Report #002: Node Drain

**Date:** TBD (run when cluster is live)
**Duration:** 10 minutes
**Participants:** Platform team
**Environment:** dev

---

## Hypothesis

> If a node is cordoned and drained (simulating spot interruption or hardware
> failure), all pods are rescheduled to healthy nodes within 2 minutes.
> Karpenter provisions a replacement node if needed. Zero user-visible errors
> occur during the entire process.

## Steady-State Definition

| Metric | Expected Value | Source |
|--------|---------------|--------|
| Error rate (5xx) | < 1% | Prometheus |
| product-api health | 200 OK continuously | HTTP probe |
| storefront health | 200 OK continuously | HTTP probe |
| Ready nodes | >= 2 | `kubectl get nodes` |
| Pod disruption budget | Respected (never 0 available) | `kubectl get pdb` |

## Experiment Configuration

| Parameter | Value |
|-----------|-------|
| Chaos type | node-drain |
| Target | 1 node running product-api pods |
| Duration | 120 seconds (node stays cordoned) |
| Probes | HTTP health (both services), Prometheus SLO, node recovery |

## Pre-Chaos Checks

- [ ] Cluster has >= 3 nodes (drain 1, keep 2)
- [ ] product-api pods are spread across multiple nodes (verify anti-affinity)
- [ ] PDBs exist for all services (`kubectl get pdb -n commerce`)
- [ ] Karpenter is running and healthy
- [ ] Grafana dashboards are open (Golden Signals + Cluster Health)

## Execution

```bash
# Verify pod distribution across nodes
kubectl get pods -n commerce -o wide

# Apply the experiment
kubectl apply -f chaos/experiments/node-drain.yaml

# Watch node status
kubectl get nodes -w

# Watch pod rescheduling
kubectl get pods -n commerce -w

# Monitor ChaosResult
kubectl get chaosresult -n commerce -w
```

## Timeline

| Time | Event | Observation |
|------|-------|-------------|
| T+0s | ChaosEngine created | — |
| T+5s | Target node cordoned (unschedulable) | — |
| T+10s | Pod eviction begins | — |
| T+Xs | Pods rescheduled to other nodes | — |
| T+Xs | Karpenter detects capacity need | — |
| T+Xs | New node joins cluster | — |
| T+120s | Node uncordoned | — |
| T+150s | All probes evaluated | — |

## Results

| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Error rate | < 1% | TBD | TBD |
| product-api health | Continuous 200 | TBD | TBD |
| storefront health | Continuous 200 | TBD | TBD |
| Pod reschedule time | < 2 min | TBD | TBD |
| Karpenter node launch | < 2 min | TBD | TBD |
| PDB respected | Yes | TBD | TBD |

**ChaosResult:** TBD (Pass / Fail)

## Analysis

### What this validates
- **PDB enforcement**: Kubernetes should refuse to evict pods if it would violate
  the PDB (minAvailable). This prevents all replicas from being evicted at once.
- **Anti-affinity**: pods should be on different nodes, so draining one node
  doesn't take down the entire service.
- **Karpenter responsiveness**: how quickly does Karpenter detect insufficient
  capacity and launch a new node?
- **Graceful shutdown**: do application pods handle SIGTERM correctly (finish
  in-flight requests, close DB connections)?

### What went well
-

### What surprised us
-

### What failed
-

## Action Items

| # | Action | Owner | Priority | Status |
|---|--------|-------|----------|--------|
| 1 | — | — | — | — |

## Follow-up Experiments

1. **Drain 2 of 3 nodes simultaneously** — does the PDB prevent total outage?
2. **Drain during peak load** — can the surviving nodes handle 3x traffic?
3. **Drain with Karpenter disabled** — what happens without auto-provisioning?
4. **Spot interruption simulation** — 2-minute warning (real AWS spot behavior)

## References

- Experiment manifest: `chaos/experiments/node-drain.yaml`
- Karpenter config: `kubernetes/platform/karpenter/`
- PDB definitions: `kubernetes/base/*/pdb.yaml` (if exists) or in deployment spec
- [Litmus Node Drain docs](https://litmuschaos.github.io/litmus/experiments/node-drain/)
