# ADR-006: Use Loki over ELK for Log Aggregation

**Date:** 2026-03-25
**Status:** Accepted

---

## Context

With Prometheus collecting metrics and Grafana providing dashboards, we need a
log aggregation system to centralize container logs from all services and nodes.
During incidents, engineers need to correlate metrics ("error rate spiked at 14:03")
with logs ("what error messages appeared at 14:03?") in a single interface.

The two dominant approaches for Kubernetes log aggregation are Loki (Grafana's
log system) and the ELK stack (Elasticsearch, Logstash/Fluentd, Kibana).

---

## Decision

We will use **Loki** (with Promtail for collection and Grafana for querying).

---

## Options Considered

### Option A: Loki + Promtail + Grafana

Loki is a log aggregation system designed by Grafana Labs. Its core insight:
index only the metadata (labels), not the log content. Query-time grep replaces
write-time indexing.

**Pros:**
- **Label-only indexing**: Loki indexes log stream labels (namespace, pod, app)
  but stores log lines as compressed chunks without indexing the content. This
  means 10-100x less storage and index overhead compared to Elasticsearch.
- **Same UI as metrics**: logs are queried in Grafana via LogQL. Engineers use
  one tool for metrics (PromQL) and logs (LogQL) — no context-switching to
  Kibana. During incidents, split-screen metrics + logs in the same dashboard.
- **LogQL is PromQL-adjacent**: if you know PromQL, LogQL is intuitive.
  `{namespace="commerce", app="product-api"} |= "error" | json | status >= 500`
- **Lightweight**: Loki SingleBinary runs in one pod with ~256Mi memory.
  Elasticsearch needs a minimum 3-node cluster with 2+ GB heap per node.
- **Kubernetes-native labels**: Promtail auto-discovers pods and adds namespace,
  pod name, container name, and app labels. No manual log parsing config.
- **Cost**: storage cost scales with log volume, not query complexity. A grep
  over compressed chunks is cheap. Elasticsearch's inverted index is expensive
  to build and store.
- **Grafana integration**: Loki is a first-class Grafana data source. Log
  context links, live tail, and log-to-trace correlation work out of the box.

**Cons:**
- **No full-text search index**: queries that grep large time ranges are slower
  than Elasticsearch's indexed lookups. "Find all logs containing 'NullPointerException'
  in the last 30 days" is fast in ELK, slow in Loki.
- **Less mature ecosystem**: Loki's ecosystem (alerting on logs, log-based
  dashboards) is growing but smaller than ELK's.
- **Label cardinality sensitivity**: too many unique label combinations create
  too many streams, degrading performance. Must be disciplined about which
  fields become labels vs. stay as log content.
- **No built-in log analytics**: Elasticsearch/Kibana has Lens, ML anomaly
  detection, and aggregation-based visualizations. Loki is query-and-grep.

### Option B: ELK Stack (Elasticsearch + Fluentd + Kibana)

The ELK stack (or EFK with Fluentd) is the traditional log aggregation solution.
Elasticsearch indexes every word in every log line, enabling full-text search.

**Pros:**
- **Full-text search**: every word is indexed. Arbitrary searches across all
  logs are fast, regardless of time range. Powerful for forensic analysis.
- **Kibana**: rich visualization, Lens for ad-hoc exploration, saved searches,
  ML-based anomaly detection on log patterns.
- **Aggregations**: Elasticsearch can aggregate log data (count errors per
  endpoint, average response time from access logs). Loki can do this with
  metric queries but it's less natural.
- **Mature ecosystem**: 10+ years of production use, massive community, extensive
  documentation, commercial support (Elastic Cloud).
- **Alerting**: Elasticsearch has built-in alerting on log patterns (Watcher /
  Elastic Alerting). More mature than Loki's ruler.

**Cons:**
- **Resource hungry**: minimum viable Elasticsearch cluster is 3 nodes with
  2 GB heap each = 6 GB memory just for Elasticsearch. Plus Kibana (1 GB),
  Fluentd DaemonSet. Total: ~8-10 GB memory overhead.
- **Storage cost**: full-text indexing means the index is often larger than the
  raw logs. A 1 GB/day log volume can require 3-5 GB/day of storage (raw +
  index + replicas).
- **Operational complexity**: Elasticsearch requires careful tuning — shard
  sizing, index lifecycle management (ILM), mapping explosions, JVM heap
  tuning, cluster rebalancing. This is a part-time job.
- **Separate UI**: Kibana is a separate application from Grafana. During
  incidents, engineers switch between Grafana (metrics) and Kibana (logs) —
  two tabs, two query languages, two mental models.
- **License concerns**: Elasticsearch changed from Apache 2.0 to SSPL in 2021.
  OpenSearch (AWS fork) exists but fragments the ecosystem.

### Option C: CloudWatch Logs

Use AWS CloudWatch Logs natively — Fluent Bit ships logs to CloudWatch,
query via CloudWatch Logs Insights.

**Pros:** Zero infrastructure to manage, native AWS integration, pay-per-use

**Cons:**
- CloudWatch Logs Insights is limited compared to LogQL or Kibana
- $0.50/GB ingestion + $0.03/GB storage — expensive at scale
- Vendor lock-in — logs are in AWS, not portable
- Separate UI from Grafana (CloudWatch can be a Grafana data source, but
  the experience is inferior to native Loki)
- Eliminated — cost and query limitations don't justify the operational savings

---

## Rationale

**Loki wins on operational simplicity, cost, and unified observability:**

1. **One UI for everything**: with Loki, engineers see metrics and logs in
   Grafana side-by-side. During a 2 AM incident, they don't switch between
   Grafana and Kibana — they see "error rate spiked" and click through to
   the actual error logs in the same dashboard. This reduces mean time to
   diagnose (MTTD).

2. **10x less resources**: Loki SingleBinary uses ~256 Mi memory. An equivalent
   Elasticsearch setup needs ~8 GB. For a dev environment on t3.medium nodes
   (4 GB memory each), Elasticsearch would consume an entire node just for
   logging. Loki fits alongside the application workloads.

3. **Storage cost at scale**: with label-only indexing, Loki stores 1 GB of
   logs in roughly 1 GB of storage (compressed). Elasticsearch stores 1 GB
   of logs in 3-5 GB (raw + inverted index + replicas). At 10 GB/day log
   volume, this is the difference between 50 GB/month and 150-250 GB/month
   in EBS costs.

4. **No full-text search is acceptable**: our services log structured JSON.
   Structured log queries (`| json | level="error" | status >= 500`) are fast
   in Loki because they grep compressed chunks with known structure. The
   scenario where ELK wins — unstructured, high-cardinality text search across
   months of data — doesn't apply to this project.

5. **Label model matches Kubernetes**: Loki's label-based stream model
   (namespace, pod, container, app) maps directly to Kubernetes metadata.
   Promtail auto-discovers this. No manual log parsing rules, no Fluentd
   filter chains, no Logstash grok patterns.

**Why not ELK?**
ELK is the right choice when: (a) full-text search across months of data is a
hard requirement, (b) log-based analytics and ML anomaly detection are needed,
(c) the team already operates Elasticsearch, or (d) compliance requires
long-term searchable log archives. None of these apply here. ELK's power comes
with operational cost that isn't justified for this project's scale.

---

## Consequences

### Positive
- Single Grafana UI for metrics, logs, and traces (with OpenTelemetry, Task 38)
- ~256 Mi memory overhead vs ~8 GB for ELK
- LogQL queries alongside PromQL in the same dashboard
- Promtail auto-discovers pods — zero per-service log configuration
- Storage scales linearly with log volume, not query complexity

### Negative
- No full-text index — arbitrary text searches over large time ranges are slower
- Kibana's visualization capabilities (Lens, ML) are not available
- Loki's alerting on logs (ruler) is less mature than Elasticsearch Watcher
- Must be disciplined about label cardinality — too many labels degrade performance

### Risks
- **Log volume spike**: a misconfigured service could flood Loki with logs.
  *Mitigation*: per-stream rate limits (10 MB/s) in Loki config, debug log
  dropping in Promtail pipeline.

- **Slow queries on wide time ranges**: a `|=` grep across 14 days of logs
  can be slow if there are many streams.
  *Mitigation*: use label selectors to narrow the search before grep. Train
  engineers to query like `{app="product-api"} |= "error"` not `{} |= "error"`.

---

## Implementation Notes

```
observability/loki/
├── values-loki.yaml      # Loki Helm values (SingleBinary, TSDB, 14d retention)
└── values-promtail.yaml  # Promtail Helm values (DaemonSet, JSON pipeline)
```

**Install sequence:**
```bash
helm install loki grafana/loki -n monitoring -f observability/loki/values-loki.yaml
helm install promtail grafana/promtail -n monitoring -f observability/loki/values-promtail.yaml
```

**Grafana data source** (pre-configured in Task 34):
```yaml
additionalDataSources:
  - name: Loki
    type: loki
    url: http://loki-gateway.monitoring:80
```

**Example LogQL queries:**
```
# All error logs from product-api
{namespace="commerce", app="product-api"} | json | level="error"

# 5xx responses in the last hour
{namespace="commerce"} | json | status >= 500

# Request rate from logs (metric query)
sum(rate({namespace="commerce"} | json | __error__="" [5m])) by (app)
```

---

## References

- [Loki documentation](https://grafana.com/docs/loki/latest/)
- [LogQL documentation](https://grafana.com/docs/loki/latest/logql/)
- [Loki vs Elasticsearch — Grafana Labs comparison](https://grafana.com/blog/2020/10/28/loki-2.0-released-transform-logs-as-youre-querying-them-and-set-up-alerts-within-loki/)
- [Loki configuration](observability/loki/) — Task 36
