# Game Day Report #001: Pod Kill — product-api

**Date:** TBD (run when cluster is live)
**Duration:** 5 minutes
**Participants:** Platform team
**Environment:** dev

---

## Hypothesis

> If one product-api pod is forcefully killed (SIGKILL), the remaining pods
> will handle all traffic with zero user-visible errors. Kubernetes will
> schedule a replacement pod that reaches Ready state within 30 seconds.

## Steady-State Definition

| Metric | Expected Value | Source |
|--------|---------------|--------|
| Error rate (5xx) | < 1% | Prometheus: `rate(http_requests_total{status=~"5.."}[1m])` |
| P99 latency | < 500ms | Prometheus: `histogram_quantile(0.99, ...)` |
| Healthy pods | >= 1 | `kubectl get pods -l app=product-api` |
| Health endpoint | 200 OK | `curl product-api.commerce.svc.cluster.local/healthz` |

## Experiment Configuration

| Parameter | Value |
|-----------|-------|
| Chaos type | pod-delete (force kill / SIGKILL) |
| Target | product-api deployment |
| Pods affected | 50% (1 of 2 pods) |
| Chaos duration | 60 seconds |
| Kill interval | 30 seconds between kills |
| Probes | HTTP health, Prometheus SLO, minimum pod count |

## Pre-Chaos Checks

- [ ] product-api has >= 2 running pods
- [ ] Health endpoint returns 200
- [ ] Error rate is 0%
- [ ] Grafana Golden Signals dashboard is open
- [ ] Prometheus alerting rules are active

## Execution

```bash
# Apply the chaos experiment
kubectl apply -f chaos/experiments/pod-kill-product-api.yaml

# Watch in real-time
kubectl get pods -n commerce -l app.kubernetes.io/name=product-api -w

# Monitor the ChaosResult
kubectl get chaosresult -n commerce -w

# Check Grafana: Golden Signals dashboard for error rate and latency
```

## Timeline

| Time | Event | Observation |
|------|-------|-------------|
| T+0s | Chaos engine started | — |
| T+5s | Pod killed (SIGKILL) | — |
| T+Xs | New pod scheduled | — |
| T+Xs | New pod reaches Ready | — |
| T+30s | Second pod kill | — |
| T+60s | Chaos duration ends | — |
| T+90s | All probes evaluated | — |

*Fill in observations when running the experiment.*

## Results

| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Error rate | < 1% | TBD | TBD |
| P99 latency | < 500ms | TBD | TBD |
| Pod recovery time | < 30s | TBD | TBD |
| Health probe | Continuous 200 | TBD | TBD |

**ChaosResult:** TBD (Pass / Fail)

## Analysis

*To be filled after running the experiment.*

### What went well
-

### What surprised us
-

### What failed (if anything)
-

## Action Items

| # | Action | Owner | Priority | Status |
|---|--------|-------|----------|--------|
| 1 | — | — | — | — |

## Lessons Learned

*Key takeaways for the team.*

---

## Follow-up Experiments

After this experiment succeeds, escalate:
1. **Kill 100% of pods** — does HPA recover from zero?
2. **Kill during rolling deployment** — does the deployment complete?
3. **Kill with load** — does the surviving pod handle 2x traffic?

## References

- Experiment manifest: `chaos/experiments/pod-kill-product-api.yaml`
- SLO rules: `observability/prometheus/custom-rules/slo-product-api.yaml`
- Golden Signals dashboard: `observability/grafana/dashboards/golden-signals.json`
- [Litmus Pod Delete docs](https://litmuschaos.github.io/litmus/experiments/pod-delete/)
