# MaxWeather — AWS Infrastructure Architecture

## Infrastructure Diagram

<img src="maxwheather.drawio.svg" width="100%" alt="MaxWeather Infrastructure Architecture" />

---

## Scaling Strategy

### Reactive Scaling (HPA + KEDA)

Handles unexpected traffic spikes by scaling based on real-time metrics:

- **HPA**: scales pods when CPU utilization ≥ 70%
- **KEDA**: scales pods based on HTTP request/s — more precise than CPU alone
- **Cluster Autoscaler**: adds or removes EC2 nodes when pods are pending

Limitation: 2–5 minute cold start when a sudden peak arrives.

---

### Scheduled Scaling (Proactive)

Since the morning peak is **predictable** (7–9am daily), the system pre-scales before traffic arrives — eliminating cold start entirely.

#### Timeline

```
00:00  Night mode        Pods: 2  · Nodes: 2 On-Demand
06:00  Pre-warm nodes    AWS Scheduled Action → add 4 nodes (~3 min to become ready)
06:30  Pre-warm pods     KEDA CronScaler → scale pods: 2 → 12
07:00  Morning peak      System fully ready, zero cold start
                         HPA + KEDA take over if additional scaling is needed
09:30  Peak ends         CronScaler expires → HPA gradually scales down by CPU
10:30  Scale down nodes  AWS Scheduled Action → reduce to 3 Reserved nodes
22:00  Night mode        Pods: 2  · Nodes: 2
```

#### Layer 1 — KEDA CronScaler (Pod level)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: weather-service-scheduled-scaler
  namespace: weather-prod
spec:
  scaleTargetRef:
    name: weather-service
  minReplicaCount: 3
  maxReplicaCount: 20
  triggers:
    - type: cron                          # Weekday morning peak
      metadata:
        timezone: Asia/Ho_Chi_Minh
        start: 30 6 * * 1-5              # 6:30am Mon–Fri
        end:   30 9 * * 1-5              # 9:30am Mon–Fri
        desiredReplicas: "12"
    - type: cron                          # Weekend (~40% lower traffic)
      metadata:
        timezone: Asia/Ho_Chi_Minh
        start: 30 7 * * 6,0              # 7:30am Sat–Sun
        end:   30 10 * * 6,0             # 10:30am Sat–Sun
        desiredReplicas: "7"
    - type: cpu                           # Reactive fallback
      metricType: Utilization
      metadata:
        value: "70"
```

#### Layer 2 — AWS Scheduled Scaling (Node level)

| Action | Schedule (UTC+7) | Min | Max | Desired |
|--------|-----------------|-----|-----|---------|
| pre-warm | 06:00 Mon–Fri | 6 | 10 | 6 |
| post-peak | 10:30 Mon–Fri | 3 | 7 | 3 |
| weekend-warm | 07:30 Sat–Sun | 4 | 8 | 4 |
| weekend-down | 10:30 Sat–Sun | 3 | 7 | 3 |
| night-mode | 22:00 daily | 2 | 4 | 2 |

#### CronScaler + HPA Conflict Resolution

```
CronScaler desiredReplicas: 12
      ↕  higher value wins
HPA CPU-based:               8
─────────────────────────────────
Result: 12 pods

When CronScaler expires at 9:30am:
→ HPA takes over and gradually scales down based on CPU
→ No sudden replica drop
```

#### Comparison

| Metric | Reactive Only | Scheduled + Reactive |
|--------|--------------|----------------------|
| Cold start at 7am | 2–5 minutes | 0 seconds |
| P99 latency at peak start | 5–10s | < 200ms |
| Cost | Baseline | ~15% higher |
| Reliability at peak | Low | High |

#### Terraform Module

```
modules/
└── scheduled-scaling/
    ├── keda-scaledobject.yaml
    ├── asg-scheduled-action.tf
    └── variables.tf              # timezone, peak_start, peak_end, peak_replicas
```

---

## Traffic Flow

### Inbound (User Request)
```
User → Route 53 → CloudFront (TTL 10min)
                      │ cache miss
                      ▼
               API Gateway → Lambda Authorizer → DynamoDB (key lookup)
                      │ authorized
                      ▼
               Internet Gateway → ALB → Nginx Ingress → weather-service Pod
                                                              │
                                              ┌───────────────┴───────────────┐
                                              │                               │
                                        Valkey HIT                       Valkey MISS
                                        return cached                         │
                                                                    NAT → OpenWeatherMap
                                                                              │
                                                                      write to Valkey
                                                                       (TTL 10min)
```
Valkey runs as a **Replication Group, Cluster Mode Disabled** (1 shard). Staging: 1 primary node, no replica. Production: 1 primary (AZ-a) + 1 replica (AZ-b), automatic failover enabled. Single-shard is sufficient — the workload is read-heavy with TTL writes; no need to partition keyspace across multiple shards.
```
```

### Outbound (CI/CD)
```
Jenkins → ECR (push image) → Pods (pull image)
Jenkins → EKS Control Plane (kubectl apply) → Schedule Pods
Jenkins → S3 (store artifacts)
```

### Observability
```
Pods → Fluent Bit → CloudWatch Logs
Pods → CloudWatch Metrics → Alarms → SNS
GuardDuty + AWS Config → Security Hub
CloudTrail → Audit all API calls
```

---

## Component Summary

| Layer | Component | Purpose |
|-------|-----------|---------|
| **Edge** | Route 53 | DNS, health check routing |
| **Edge** | CloudFront | CDN, cache TTL 10min |
| **Edge** | WAF | OWASP protection, rate limit per IP |
| **Edge** | ACM | SSL/TLS certificates |
| **Auth** | API Gateway | Throttle, cache, proxy |
| **Auth** | Lambda Authorizer | Verify Bearer token |
| **Auth** | DynamoDB | API key store |
| **Auth** | Secrets Manager | Credentials management |
| **Auth** | KMS | Encryption key management |
| **Network** | VPC | Isolated network (ap-southeast-1) |
| **Network** | ALB | Load balancing, Multi-AZ |
| **Network** | NAT Gateway ×3 | Outbound internet per AZ |
| **Network** | VPC Endpoints | Private access to AWS services |
| **Compute** | EKS Control Plane | Kubernetes API server (managed) |
| **Compute** | Node Group Reserved | 3 × m7i.xlarge, base capacity |
| **Compute** | Node Group On-Demand | 0–7 × m7i.large, burst |
| **Compute** | Nginx Ingress | HTTP routing into cluster |
| **Compute** | weather-service | Application pods, HPA 3→20 replicas |
| **Compute** | KEDA | Event-driven autoscaler (HTTP req/s + cron) |
| **Compute** | Cluster Autoscaler | Add/remove EC2 nodes |
| **Compute** | Fluent Bit | Log shipping to CloudWatch |
| **Data** | Aurora PostgreSQL | OAuth2 clients, saved locations, weather alerts |
| **Data** | ElastiCache Valkey | Weather cache TTL 10min, rate limit counters |
| **Data** | S3 | Terraform state, Jenkins artifacts |
| **CI/CD** | Jenkins EC2 | Build, test, deploy pipeline |
| **CI/CD** | ECR | Container image registry |
| **Observability** | CloudWatch | Logs, metrics, alarms, dashboard |
| **Observability** | CloudTrail | API audit trail (SOC2, ISO27001) |
| **Observability** | GuardDuty | Threat detection |
| **Observability** | Security Hub | Aggregate security findings |
| **Observability** | AWS Config | CIS compliance rules |
| **Observability** | SNS | Alert notifications |
| **External** | OpenWeatherMap | Third-party weather data source |

---

## Infrastructure Sizing

### Staging

| Component | Instance Type | Spec | Count | Billing |
|-----------|--------------|------|-------|---------|
| **EKS Node Group** | `m7i.large` | 2 vCPU / 8 GB | 2 nodes | On-Demand |
| **Aurora PostgreSQL** | `db.t4g.medium` | 2 vCPU / 4 GB | 1 writer, no reader | On-Demand |
| **ElastiCache Valkey** | `cache.t4g.medium` | 2 vCPU / 3.09 GB | 1 node, single AZ | On-Demand |
| **NAT Gateway** | — | — | 1 shared | Per GB |
| **Jenkins EC2** | `t3.large` | 2 vCPU / 8 GB | 1 | On-Demand |
| **API Gateway throttle** | — | 100 req/s | — | Per request |
| **Lambda Authorizer** | — | 128 MB · timeout 5s | — | Per invocation |
| **CloudFront cache** | — | TTL 10min · cache disabled for testing | — | Per request |

---

### Production

| Component | Instance Type | Spec | Count | Billing |
|-----------|--------------|------|-------|---------|
| **EKS Node Group — Base** | `m7i.xlarge` | 4 vCPU / 16 GB | 3 nodes | Reserved 1-year |
| **EKS Node Group — Burst** | `m7i.large` | 2 vCPU / 8 GB | 0–7 nodes | On-Demand |
| **Aurora PostgreSQL — Writer** | `db.r7g.large` | 2 vCPU / 16 GB | 1 · AZ-a | Reserved 1-year |
| **Aurora PostgreSQL — Reader** | `db.r7g.large` | 2 vCPU / 16 GB | 1 · AZ-b | Reserved 1-year |
| **ElastiCache Valkey — Primary** | `cache.r7g.large` | 2 vCPU / 13.07 GB | 1 · AZ-a | Reserved 1-year |
| **ElastiCache Valkey — Replica** | `cache.r7g.large` | 2 vCPU / 13.07 GB | 1 · AZ-b · auto failover | Reserved 1-year |
| **NAT Gateway** | — | — | 3 (1 per AZ) | Per GB |
| **Jenkins EC2** | `t3.large` | 2 vCPU / 8 GB | 1 shared with staging | On-Demand |
| **API Gateway throttle** | — | 1000 req/s | — | Per request |
| **Lambda Authorizer** | — | 256 MB · timeout 3s | — | Per invocation |
| **CloudFront cache** | — | TTL 10min · WAF enabled | — | Per request |

---

## Security Standards

| Standard | Controls Implemented |
|----------|---------------------|
| **SOC 2 Type II** | CloudTrail audit, IAM access control, Multi-AZ availability |
| **ISO 27001** | KMS encryption at rest, TLS in transit, Secrets Manager |
| **CIS AWS Benchmark** | VPC Flow Logs, no root IAM user, CloudTrail multi-region |
| **CIS Kubernetes** | Non-root pods, Pod Security Standard, Network Policy |
| **OWASP API Top 10** | WAF rules, Lambda Authorizer, API Gateway throttling |
