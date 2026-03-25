# Runbook: Database Failover

**Last updated:** 2026-03-25
**Owner:** Platform team
**Severity trigger:** Critical — RDS instance unreachable or degraded

---

## When to Use

- Alert: `ProductAPIHighErrorBurnRate` with database connection errors in logs
- RDS CloudWatch: `DatabaseConnections` dropping to 0
- AWS Health Dashboard shows RDS maintenance or AZ issue
- `kubectl logs` shows `connection refused` or `timeout` to PostgreSQL
- RDS Multi-AZ failover in progress (automatic, but verify recovery)

## Diagnosis

```bash
# 1. Check application logs for DB errors
kubectl logs -n commerce -l app.kubernetes.io/name=product-api --tail=50 | grep -i "postgres\|connection\|timeout\|refused"

# 2. Check RDS status via AWS CLI
aws rds describe-db-instances \
  --db-instance-identifier cloudnative-commerce-dev \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone,MultiAZ:MultiAZ,Endpoint:Endpoint.Address}'

# 3. Check RDS events (last 1 hour)
aws rds describe-events \
  --source-identifier cloudnative-commerce-dev \
  --source-type db-instance \
  --duration 60

# 4. Check CloudWatch metrics
# - DatabaseConnections: should be > 0
# - CPUUtilization: should be < 90%
# - FreeableMemory: should be > 100MB
# - ReadLatency / WriteLatency: should be < 20ms

# 5. Test connectivity from a pod
kubectl run db-test --rm -it --image=postgres:16-alpine -n commerce -- \
  pg_isready -h <RDS_ENDPOINT> -p 5432
```

## Procedure

### Scenario A: RDS Multi-AZ automatic failover (most common)

RDS Multi-AZ failover is **automatic** — AWS promotes the standby replica in
the other AZ. The DNS endpoint stays the same, but the IP changes.

```bash
# 1. Verify failover is in progress or completed
aws rds describe-events --source-identifier cloudnative-commerce-dev \
  --source-type db-instance --duration 60

# Look for: "Multi-AZ instance failover started" / "completed"

# 2. Application should reconnect automatically via DNS.
# If it doesn't, the connection pool may be holding stale connections.

# 3. Restart application pods to force new connections
kubectl rollout restart deployment/product-api -n commerce
kubectl rollout restart deployment/order-worker -n commerce  # if exists as deployment

# 4. Watch pods come back healthy
kubectl get pods -n commerce -w

# 5. Verify readiness probe passes (depends on DB connectivity)
kubectl get endpoints product-api -n commerce
```

### Scenario B: RDS instance degraded (not failing over)

```bash
# 1. Check if the instance is in a bad state
aws rds describe-db-instances \
  --db-instance-identifier cloudnative-commerce-dev \
  --query 'DBInstances[0].DBInstanceStatus'

# Possible states: available, backing-up, maintenance, modifying, rebooting

# 2. If status is "available" but connections fail, try a reboot
aws rds reboot-db-instance \
  --db-instance-identifier cloudnative-commerce-dev \
  --force-failover  # Forces Multi-AZ failover during reboot

# 3. Monitor reboot progress
aws rds describe-events --source-identifier cloudnative-commerce-dev \
  --source-type db-instance --duration 30

# 4. After reboot, restart app pods
kubectl rollout restart deployment/product-api -n commerce
```

### Scenario C: Connection pool exhaustion (app-side issue)

```bash
# 1. Check current connections vs max
kubectl logs -n commerce -l app.kubernetes.io/name=product-api --tail=100 | \
  grep -i "connection pool\|max connections\|too many"

# 2. Check RDS connection count
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=cloudnative-commerce-dev \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Maximum

# 3. If connections are at max, scale down pods temporarily to release connections
kubectl scale deployment product-api -n commerce --replicas=1
sleep 30
kubectl scale deployment product-api -n commerce --replicas=3

# 4. Long-term: increase RDS max_connections or add PgBouncer
```

## Verification

```bash
# Application is healthy
kubectl get pods -n commerce -l app.kubernetes.io/name=product-api
kubectl logs -n commerce -l app.kubernetes.io/name=product-api --tail=10

# API responds correctly
kubectl run curl-test --rm -it --image=curlimages/curl -n commerce -- \
  curl -s http://product-api.commerce.svc.cluster.local/healthz

# Error rate is back to normal
# Grafana: Golden Signals → Error Rate should be < 0.1%

# No 5xx errors in recent logs
kubectl logs -n commerce -l app.kubernetes.io/name=product-api --tail=100 | \
  grep -c "status.*5[0-9][0-9]"
```

## Prevention

- RDS Multi-AZ is enabled (automatic failover)
- Connection pool has timeout + retry settings
- Readiness probe checks DB connectivity (pod removed from endpoints when DB is down)
- External Secrets rotates DB credentials automatically
- RDS automated backups enabled (point-in-time recovery to 5-minute granularity)
