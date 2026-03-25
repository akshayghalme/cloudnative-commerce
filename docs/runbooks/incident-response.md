# Runbook: Incident Response

**Last updated:** 2026-03-25
**Owner:** Platform team

---

## Severity Levels

| Severity | Definition | Response Time | Examples |
|----------|-----------|---------------|---------|
| **SEV1** | Complete service outage, all users impacted | Page immediately, all hands | All pods down, DB unreachable, 100% errors |
| **SEV2** | Significant degradation, many users impacted | Page on-call, respond in 15m | >10% error rate, P99 > 2s, partial outage |
| **SEV3** | Minor degradation, some users impacted | Respond in 1h (business hours) | Elevated latency, one pod crashlooping |
| **SEV4** | No user impact, potential risk | Respond in 24h | Disk usage warning, certificate expiring |

## Incident Workflow

### 1. Detect (0-2 minutes)

Alerts arrive via:
- **PagerDuty** (SEV1/SEV2) → pages on-call engineer
- **Slack #incidents** (SEV1) → visible to all engineers
- **Slack #alerts** (SEV2-4) → monitored during business hours
- **Grafana** → anomaly spotted on dashboard

### 2. Acknowledge (2-5 minutes)

```
1. Acknowledge the PagerDuty alert
2. Post in Slack #incidents:
   "Investigating: [alert name]. I'm IC (Incident Commander)."
3. Open Grafana — Golden Signals + Cluster Health dashboards
```

### 3. Triage (5-15 minutes)

**Determine scope and severity:**

```bash
# What's broken?
kubectl get pods -n commerce
kubectl get events -n commerce --sort-by=.lastTimestamp | tail -20

# What changed recently?
# ArgoCD: check recent syncs
kubectl get applications -n argocd
# Git: check recent commits
git log --oneline -10

# What do metrics say?
# Grafana → Golden Signals: which service has elevated errors?
# Grafana → Cluster Health: are nodes healthy?
```

**Quick checks by symptom:**

| Symptom | First Check | Likely Cause |
|---------|-------------|--------------|
| 5xx errors spiking | `kubectl logs -l app=product-api` | Code bug, DB down, OOM |
| High latency | Grafana → CPU saturation | Need to scale, slow query |
| Pods crashlooping | `kubectl describe pod <pod>` | OOM kill, config error |
| All pods Pending | `kubectl describe pod <pod>` → Events | Node capacity, Karpenter limits |
| No traffic at all | `kubectl get endpoints` | Service selector mismatch, ingress down |

### 4. Mitigate (15-30 minutes)

**Goal: restore service, not find root cause.** Fix root cause later.

**Common mitigations:**

```bash
# Rollback last deployment (if deploy caused the issue)
# ArgoCD UI → Application → History → Rollback to previous sync
# OR:
git revert HEAD
git push origin main
# ArgoCD auto-syncs the revert

# Restart pods (clears transient state)
kubectl rollout restart deployment/product-api -n commerce

# Scale up (if capacity is the issue)
kubectl scale deployment product-api -n commerce --replicas=10

# Isolate a bad pod (keep it for debugging but remove from traffic)
kubectl label pod <pod-name> -n commerce app.kubernetes.io/name-

# Block a bad endpoint (via ingress annotation)
kubectl annotate ingress commerce-ingress -n commerce \
  nginx.ingress.kubernetes.io/server-snippet="location /bad-endpoint { return 503; }"
```

### 5. Communicate

**During the incident (every 15-30 minutes):**
```
Slack #incidents update:
- Status: Investigating / Identified / Mitigating / Resolved
- Impact: [who/what is affected]
- Current action: [what we're doing right now]
- ETA: [when we expect resolution, or "unknown"]
```

### 6. Resolve

```bash
# Verify all services are healthy
kubectl get pods -n commerce
kubectl get hpa -n commerce

# Verify error rate is back to normal
# Grafana → Golden Signals → Error Rate < 0.1%

# Verify no pending alerts
# Alertmanager UI or: kubectl get prometheusrules -n monitoring
```

**Post in Slack #incidents:**
```
RESOLVED: [alert name]
Duration: [start time] to [end time] ([X] minutes)
Impact: [what users experienced]
Root cause: [brief summary]
Follow-up: [post-mortem scheduled for <date>]
```

### 7. Post-Mortem (within 48 hours)

Create a failure report in `docs/failures/`:

```markdown
# Incident: [title]

**Date:** YYYY-MM-DD
**Duration:** X minutes
**Severity:** SEVX
**Impact:** [user-facing impact]

## Timeline
- HH:MM — Alert fired
- HH:MM — IC acknowledged
- HH:MM — Root cause identified
- HH:MM — Mitigation applied
- HH:MM — Service restored

## Root Cause
[What actually broke and why]

## What Went Well
- [Fast detection, effective mitigation, etc.]

## What Went Wrong
- [Slow diagnosis, missing runbook, etc.]

## Action Items
| # | Action | Owner | Due Date | Status |
|---|--------|-------|----------|--------|
| 1 | [Prevent recurrence] | — | — | Open |
| 2 | [Improve detection] | — | — | Open |
```

## Quick Reference

### Key URLs
| Resource | URL |
|----------|-----|
| Grafana | `https://grafana.cloudnative-commerce.dev` |
| ArgoCD | `https://argocd.cloudnative-commerce.dev` |
| PagerDuty | `https://app.pagerduty.com` |
| AWS Console | `https://ap-south-1.console.aws.amazon.com` |
| GitHub Actions | `https://github.com/akshayghalme/cloudnative-commerce/actions` |

### Key Commands
```bash
# Service health
kubectl get pods -n commerce
kubectl top pods -n commerce

# Recent events
kubectl get events -n commerce --sort-by=.lastTimestamp | tail -20

# Logs (last 5 minutes)
kubectl logs -n commerce -l app.kubernetes.io/name=product-api --since=5m

# ArgoCD sync status
kubectl get applications -n argocd

# Node health
kubectl get nodes
kubectl top nodes
```
