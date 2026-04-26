# MaxWeather — DevOps Technical Assessment

## Table of Contents

- [Project Overview](#project-overview)
- [Design Overview](#design-overview)
- [Folder Structure](#folder-structure)
- [Prerequisites](#prerequisites)
- [Environment Variables](#environment-variables)
- [Coding Standards](#coding-standards)
- [Component 1 — Application (weather-service)](#component-1--application-weather-service)
- [Component 2 — Terraform Infrastructure](#component-2--terraform-infrastructure)
- [Component 3 — Kubernetes Manifests](#component-3--kubernetes-manifests)
- [Component 4 — Jenkins Pipeline](#component-4--jenkins-pipeline)
- [Component 5 — API Gateway](#component-5--api-gateway)
- [Component 6 — Postman Collection](#component-6--postman-collection)
- [Real AWS Test Results](#real-aws-test-results)
- [Architecture Compliance Audit](#architecture-compliance-audit)

---

## Project Overview

MaxWeather is a weather forecast platform deployed on AWS using Kubernetes (EKS) as the container orchestration platform. The system exposes weather forecast APIs protected by Bearer token auth via Lambda Authorizer, supports high availability across multiple Availability Zones, and auto-scales based on traffic — including scheduled pre-warming before the morning peak (7–9am UTC+7).

---

## Design Overview

Full architecture: [design/architecture.md](design/architecture.md) · Diagram: [design/maxwheather.drawio.svg](design/maxwheather.drawio.svg)

### Core Problem

Weather data is fetched from a third-party API (OpenWeatherMap) on every request. At morning peak (7–9am UTC+7), concurrent requests spike sharply and predictably. Two problems must be solved simultaneously: **external API cost and latency** (solved by Valkey cache, TTL 10min) and **cold-start delay at peak** (solved by scheduled pre-warming, not reactive scaling alone).

### Key Design Decisions

**Auth — Lambda Authorizer over API Key native validation**
API Gateway's native API key mechanism offers no per-key revocation granularity and no audit trail. The Lambda Authorizer reads from DynamoDB on each request, enabling real-time key status checks (`active` flag), per-key access control, and a full CloudTrail audit trail. Latency overhead is absorbed by API Gateway's authorizer cache (TTL 600s).

**Cache — ElastiCache Valkey over in-process cache**
In-process cache (e.g. Python dict) would not survive pod restarts and would be duplicated across all pod replicas — each replica would independently call OpenWeatherMap for the same city. Valkey is shared across all pods, so a cache hit by any pod benefits all. TTL 10min matches CloudFront's CDN TTL upstream.

**Scaling — Scheduled pre-warm + KEDA, not HPA alone**
HPA reacts to CPU/memory after load has already arrived — with a 2–5 minute lag for node provisioning and pod startup. Since the morning peak is predictable (daily, 7–9am), ASG Scheduled Actions warm nodes at 06:00 UTC+7 and KEDA CronScaler scales pods to 12 at 06:30 UTC+7, 30 minutes before traffic hits. HPA and KEDA CPU trigger remain active as the reactive fallback for unexpected spikes.

**IaC — Modular Terraform, environment-level variable extraction**
Each AWS service is an independent module with no cross-module hardcoding. Staging and production differ only in `terraform.tfvars` — instance sizes, AZ count, replica counts, and all scheduling parameters are variables. This prevents configuration drift and allows the same module code to serve both environments.

### Traffic Flow (Inbound)

```
User → Route 53 → CloudFront (TTL 10min)
                      │ cache miss
                      ▼
          API Gateway (throttle) → Lambda Authorizer → DynamoDB
                      │ authorized
                      ▼
          IGW → ALB → Nginx Ingress → weather-service pod
                                            │
                              ┌─────────────┴─────────────┐
                         Valkey HIT                   Valkey MISS
                         return cached          NAT → OpenWeatherMap
                                                        │
                                               write to Valkey (TTL 10min)
```

### Environment Summary

| | Staging | Production |
|--|---------|------------|
| Region | ap-southeast-1 | ap-southeast-1 |
| AZs | 2 | 3 |
| EKS nodes | `m7i.large` × 2 | `m7i.xlarge` × 3 reserved + `m7i.large` × 0–7 burst |
| Aurora | `db.t4g.medium`, writer only | `db.r7g.large`, writer (AZ-a) + reader (AZ-b) |
| Valkey | `cache.t4g.medium`, 1 shard 0 replicas | `cache.r7g.large`, 1 shard 1 replica, auto-failover |
| Pod replicas | 1–4 (HPA) | 3–20 (HPA + KEDA) |
| Log retention | 14 days | 90 days |

---

## Folder Structure

```
MaxWeather/
├── design/                              # Architecture documentation
│   ├── architecture.md                  # Full architecture doc (English)
│   ├── maxwheather.drawio.svg           # Infrastructure diagram
│   └── desc.md                          # Assessment requirements
│
├── app/                                 # weather-service application
│   ├── src/
│   │   ├── main.py                      # FastAPI entrypoint
│   │   ├── api/
│   │   │   ├── weather.py               # GET /weather, GET /forecast
│   │   │   └── health.py                # GET /health
│   │   ├── services/
│   │   │   ├── weather_service.py       # Orchestrate cache + provider
│   │   │   └── cache.py                 # Valkey wrapper
│   │   ├── providers/
│   │   │   ├── base.py                  # Abstract WeatherProvider interface
│   │   │   └── openweathermap.py        # OpenWeatherMap implementation
│   │   ├── models/
│   │   │   └── weather.py               # Pydantic schemas
│   │   └── config.py                    # Settings from environment variables
│   ├── tests/
│   │   ├── unit/
│   │   └── integration/
│   ├── Dockerfile
│   └── requirements.txt
│
├── terraform/                           # Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/                         # VPC, subnets, IGW, NAT GW, VPC Endpoints
│   │   ├── eks/                         # EKS cluster, node groups, IRSA
│   │   ├── aurora/                      # Aurora PostgreSQL 16 cluster
│   │   ├── elasticache/                 # ElastiCache Valkey 8, Multi-AZ
│   │   ├── ecr/                         # ECR repository, lifecycle policy
│   │   ├── iam/                         # IAM roles for EKS, Jenkins, Lambda
│   │   ├── kms/                         # KMS keys: aurora/elasticache/eks/s3
│   │   ├── cloudwatch/                  # Log groups, alarms, dashboard, SNS
│   │   ├── lambda-authorizer/           # Lambda function + DynamoDB API key store
│   │   └── scheduled-scaling/           # 5 ASG Scheduled Actions (UTC+7 timezone)
│   ├── environments/
│   │   ├── staging/                     # Staging: ap-southeast-1, 2 AZ
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars
│   │   └── production/                  # Production: ap-southeast-1, 3 AZ
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── terraform.tfvars
│   └── backend.tf                       # S3 remote state + DynamoDB lock
│
├── k8s/                                 # Kubernetes manifests
│   ├── base/
│   │   ├── deployment.yaml              # Production resource sizing (base)
│   │   ├── service.yaml
│   │   ├── hpa.yaml                     # CPU 70% / Memory 80%, max 20 replicas
│   │   ├── ingress.yaml
│   │   └── keda-scaledobject.yaml       # Weekday 12 pods + weekend 7 pods
│   ├── overlays/
│   │   ├── staging/                     # Patches: CPU 100m, RAM 128Mi, min=1
│   │   └── production/                  # Patches: CPU 200m, RAM 256Mi, min=3
│   └── nginx-ingress/
│       └── values.yaml                  # Helm values for Nginx Ingress Controller
│
├── jenkins/
│   └── Jenkinsfile                      # Pipeline: Build→Test→Push→Deploy→Approve→Prod
│
├── postman/
│   └── MaxWeather.postman_collection.json
│
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.12+ | Application runtime |
| Docker | 24+ | Build container images |
| Terraform | 1.7+ | Infrastructure provisioning |
| kubectl | 1.29+ | Kubernetes CLI |
| Helm | 3.14+ | Nginx Ingress Controller install |
| AWS CLI | 2.x | AWS authentication |
| kustomize | 5.x | K8s overlay management |
| KEDA | 2.x | Event-driven autoscaler |

---

## Environment Variables

**No values are hardcoded anywhere in this project.** All configuration is injected via environment variables or AWS Secrets Manager at runtime.

### Application (`app/`)

| Variable | Description | Example |
|----------|-------------|---------|
| `APP_ENV` | Environment name | `staging` / `production` |
| `APP_PORT` | Server port | `8000` |
| `WEATHER_PROVIDER` | Provider to use | `openweathermap` |
| `OPENWEATHERMAP_API_KEY` | API key (from Secrets Manager) | — |
| `OPENWEATHERMAP_BASE_URL` | Provider base URL | `https://api.openweathermap.org/data/2.5` |
| `VALKEY_HOST` | Valkey endpoint | — |
| `VALKEY_PORT` | Valkey port | `6379` |
| `VALKEY_TTL_SECONDS` | Cache TTL | `600` |
| `DB_HOST` | Aurora writer endpoint | — |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `maxweather` |
| `DB_USER` | Database user | — |
| `DB_PASSWORD` | Database password (from Secrets Manager) | — |
| `LOG_LEVEL` | Logging level | `INFO` |

### Terraform (`terraform/environments/*/terraform.tfvars`)

| Variable | Staging | Production | Notes |
|----------|---------|------------|-------|
| `aws_region` | `ap-southeast-1` | `ap-southeast-1` | |
| `vpc_cidr` | `10.1.0.0/16` | `10.0.0.0/16` | |
| `az_count` | `2` | `3` | Production uses 3 AZs for Multi-AZ NAT GW |
| `kubernetes_version` | `1.34` | `1.34` | |
| `aurora_instance_class` | `db.t4g.medium` | `db.r7g.large` | t4g = burstable, r7g = memory-optimized |
| `valkey_node_type` | `cache.t4g.medium` | `cache.r7g.large` | t4g = burstable, r7g = memory-optimized |
| `valkey_num_clusters` | `1` | `2` | Production = primary + replica |
| `eks_node_instance_type` | `m7i.large` | — | Staging: single node group |
| `eks_reserved_instance_type` | — | `m7i.xlarge` | Production: reserved base nodes |
| `eks_burst_instance_type` | — | `m7i.large` | Production: burst on-demand nodes |
| `eks_reserved_min/max/desired` | — | `3/6/3` | |
| `eks_burst_min/max/desired` | — | `0/7/0` | |
| `log_retention_days` | `14` | `90` | |
| `schedule_weekday_peak` | `{2,4,3}` | `{6,10,6}` | min/max/desired during weekday pre-warm |
| `schedule_weekday_offpeak` | `{1,4,2}` | `{3,7,3}` | min/max/desired after weekday peak |
| `schedule_weekend_peak` | `{2,4,2}` | `{4,8,4}` | min/max/desired during weekend warm |
| `schedule_weekend_offpeak` | `{1,4,1}` | `{3,7,3}` | min/max/desired after weekend peak |
| `schedule_night` | `{1,4,1}` | `{2,4,2}` | min/max/desired night mode (22:00 UTC+7) |

---

## Coding Standards

### General

- **No hardcoded values** — all config via environment variables or AWS Secrets Manager
- **No credentials in code** — no API keys, passwords, or tokens in source files
- **No credentials in git** — `.env` files are gitignored; use `.env.example` as template
- **Fail fast** — validate required env vars at application startup; exit with clear error if missing
- **Single responsibility** — each file/module has one clear purpose
- **Meaningful names** — no abbreviations unless universally understood (e.g., `db`, `api`)

### Python (app/)

- Follow **PEP 8**; use `ruff` for linting, `black` for formatting
- Use **Pydantic** for all request/response schemas — no raw dicts across boundaries
- Use **abstract base class** for `WeatherProvider` — never call OpenWeatherMap directly from service layer
- Use **async/await** throughout — no blocking I/O on the event loop
- Use **httpx** (async) for external HTTP calls — not `requests`
- All secrets loaded via `config.py` using `pydantic-settings` — not `os.getenv()` scattered across files

### Terraform

- Each module exposes only what downstream modules need via `outputs.tf`
- Use **`locals`** for computed values — not inline expressions in resource blocks
- Tag every resource with: `environment`, `project`, `managed_by = "terraform"`
- Remote state on S3 with DynamoDB locking — no local state
- Sensitive outputs marked `sensitive = true`
- All resource sizing driven by `terraform.tfvars` — no hardcoded instance types or counts

### Kubernetes

- All resource requests and limits defined per environment — no unbounded pods
- `readinessProbe` and `livenessProbe` on every container
- `securityContext` on every pod: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`
- Use `kustomize` overlays for environment differences — no duplicated YAML
- All image references use digest or explicit tag — never `latest`

---

## Component 1 — Application (weather-service)

### API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/weather?city={city}&units={metric\|imperial}` | Bearer token | Current weather |
| `GET` | `/forecast?city={city}&days={1-7}&units={metric\|imperial}` | Bearer token | Multi-day forecast |
| `GET` | `/health` | None | Health check for probes |

### Response Format

```json
{
  "status": "success",
  "cached": true,
  "cache_ttl_seconds": 487,
  "source": "OpenWeatherMap",
  "timestamp": "2026-04-24T07:00:00Z",
  "data": {}
}
```

### Local Development

```bash
# 1. Copy env template
cp app/.env.example app/.env
# Fill in OPENWEATHERMAP_API_KEY and other values

# 2. Install dependencies
cd app && pip install -r requirements.txt

# 3. Run
uvicorn src.main:app --reload --port 8000

# 4. Test endpoints
curl http://localhost:8000/health
curl -H "Authorization: Bearer <token>" \
  "http://localhost:8000/weather?city=Hanoi&units=metric"
```

### Build & Test

```bash
# Lint
ruff check app/src/
black --check app/src/

# Unit tests (12 tests)
pytest app/tests/unit/ -v --cov=src --cov-report=term-missing

# Build Docker image (multi-stage, Python venv, non-root user)
docker build -t weather-service:local app/

# Verify non-root user
docker run --rm weather-service:local whoami   # → appuser

# Verify health endpoint
docker run --rm -p 8000:8000 --env-file app/.env weather-service:local &
curl http://localhost:8000/health
```

---

## Component 2 — Terraform Infrastructure

### Module Dependency Order

```
kms → iam → vpc → ecr
                 → aurora
                 → elasticache
                 → eks → cloudwatch
                       → lambda-authorizer
                       → scheduled-scaling
```

### Usage

```bash
# Initialize backend
cd terraform/environments/staging
terraform init

# Plan — always review before apply
terraform plan -var-file="terraform.tfvars" -out=tfplan

# Apply
terraform apply tfplan

# Destroy (staging only — never run on production without approval)
terraform destroy -var-file="terraform.tfvars"
```

### Infrastructure Sizing

#### Staging (2 AZs, ap-southeast-1a/b)

| Component | Config | Notes |
|-----------|--------|-------|
| EKS | `m7i.large`, desired=2 | Single On-Demand node group |
| Pods | CPU 100m–500m, RAM 128Mi–512Mi | HPA min=1, max=4 |
| Aurora | `db.t4g.medium`, 1 writer, no reader | AZ-a only |
| Valkey | `cache.t4g.medium`, 1 node | 1 shard, 0 replicas — single AZ |
| NAT GW | 2 (1 per AZ) | Shared per AZ |

#### Production (3 AZs, ap-southeast-1a/b/c)

| Component | Config | Notes |
|-----------|--------|-------|
| EKS Reserved | `m7i.xlarge` × 3, ON_DEMAND | Base capacity, always running |
| EKS Burst | `m7i.large` × 0–7, ON_DEMAND | Scale up during peak |
| Pods | CPU 200m–1000m, RAM 256Mi–1Gi | HPA min=3, max=20 |
| Aurora | `db.r7g.large`, 1 writer (AZ-a) + 1 reader (AZ-b) | `create_reader=true` |
| Valkey | `cache.r7g.large` × 2 (AZ-a + AZ-b) | 1 shard, 1 replica — Multi-AZ, auto-failover |
| NAT GW | 3 (1 per AZ) | Independent per AZ |

### Scheduled Scaling — 5 Schedules (UTC+7 = UTC+7)

| Action | UTC+7 Time | UTC Cron | Production Config |
|--------|----------|----------|-------------------|
| Weekday pre-warm | 06:00 Mon-Fri | `0 23 * * 0-4` | min=6, max=10, desired=6 |
| Weekday post-peak | 10:30 Mon-Fri | `30 3 * * 1-5` | min=3, max=7, desired=3 |
| Weekend warm | 07:30 Sat-Sun | `30 0 * * 6,0` | min=4, max=8, desired=4 |
| Weekend post-peak | 10:30 Sat-Sun | `30 3 * * 6,0` | min=3, max=7, desired=3 |
| Night mode | 22:00 daily | `0 15 * * *` | min=2, max=4, desired=2 |

Nodes are pre-warmed **30 minutes before** KEDA CronScaler fires pods, allowing EKS node registration to complete before pod scheduling.

### KEDA ScaledObject — Scaling Triggers

| Trigger | Type | Config |
|---------|------|--------|
| CPU reactive | CPU utilization | threshold=70%, fires immediately on spike |
| Weekday pre-warm | CronScaler | 06:30–09:30 UTC+7 Mon-Fri, desiredReplicas=12 |
| Weekend pre-warm | CronScaler | 07:30–10:30 UTC+7 Sat-Sun, desiredReplicas=7 |

After CronScaler window ends, `restoreToOriginalReplicaCount: true` hands control back to HPA (CPU-based), preventing sudden replica drops.

### KMS Key Policy Design

Each KMS key requires explicit service principal grants — the default `kms:*` for root is **not sufficient** for CloudWatch Logs and SNS. The module creates 3 IAM policy statements per key:

```
Statement 1 — RootAccess       : arn:aws:iam::{account}:root → kms:*
Statement 2 — AllowCloudWatchLogs : logs.{region}.amazonaws.com → Encrypt/Decrypt/GenerateDataKey
              (with condition: kms:EncryptionContext:aws:logs:arn)
Statement 3 — AllowSNS         : sns.amazonaws.com → GenerateDataKey + Decrypt
```

Without Statement 2, `aws_cloudwatch_log_group` with `kms_key_id` returns `AccessDeniedException` on real AWS (LocalStack does not enforce this).

---

## Component 3 — Kubernetes Manifests

### Apply to Cluster

```bash
# Configure kubectl
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name maxweather-<env>

# Install Nginx Ingress Controller (first time only)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -f k8s/nginx-ingress/values.yaml \
  --namespace ingress-nginx --create-namespace

# Apply staging
kubectl apply -k k8s/overlays/staging/

# Apply production
kubectl apply -k k8s/overlays/production/
```

### Resource Sizing by Environment

| Setting | Base (default) | Staging overlay | Production overlay |
|---------|---------------|-----------------|-------------------|
| `replicas` | 2 | 2 | 3 |
| CPU request | 200m | **100m** | **200m** |
| CPU limit | 1000m | 500m | 1000m |
| RAM request | 256Mi | **128Mi** | **256Mi** |
| RAM limit | 1Gi | 512Mi | 1Gi |
| HPA minReplicas | 2 | **1** | **3** |
| HPA maxReplicas | 20 | **4** | **20** |

### topologySpreadConstraints

Pods use `topology.kubernetes.io/zone` for zone-level spreading (`maxSkew: 1, DoNotSchedule`). Requires nodes to be labeled with zone — done automatically by EKS node groups. For local kind testing, label nodes manually:

```bash
kubectl label node maxweather-test-worker topology.kubernetes.io/zone=ap-southeast-1a
kubectl label node maxweather-test-worker2 topology.kubernetes.io/zone=ap-southeast-1b
```

---

## Component 4 — Jenkins Pipeline

### Pipeline Stages

```
Checkout SCM
    ↓
Lint & Unit Tests
    ↓
Build Docker Image (tagged with Git commit SHA)
    ↓
Push to ECR
    ↓
Deploy to Staging
    ↓
Smoke Test (staging)     ← fail here = block production
    ↓
Manual Approval Gate     ← pipeline pauses for human review
    ↓
Deploy to Production
    ↓
Health Check (production)
```

### Key Behaviors

- Failed unit tests abort pipeline before Docker build (fast fail)
- Image tagged with `${GIT_COMMIT_SHA}` — never `latest`
- Staging smoke test hits `/health` endpoint — any non-200 blocks production
- Production deploy uses rolling update (`maxUnavailable: 0`, `maxSurge: 1`)
- Jenkins uses IRSA (IAM role for service accounts) to push to ECR — no static credentials

---

## Component 5 — API Gateway

### Setup (AWS Console)

1. Create **HTTP API** (not REST API)
2. Integration: HTTP proxy → ALB DNS
3. Routes: `ANY /{proxy+}` → proxy to ALB
4. Attach **Lambda Authorizer** to all routes except `/health`
5. Enable **caching** — TTL 600s, cache key: `city` + `Authorization`
6. Set **throttling** — 1000 req/s (production), 100 req/s (staging)

### Lambda Authorizer Flow

```
API Gateway → Lambda → DynamoDB (GetItem by api_key)
                ↓
         active=true → IAM Allow policy (execute-api:Invoke)
         active=false or not found → raise Exception("Unauthorized") → 401
```

The authorizer reads `Authorization: Bearer <token>` from the HTTP header and looks up the key in the `maxweather-{env}-api-keys` DynamoDB table. Token is matched against the `api_key` partition key, and `active` boolean attribute is checked.

---

## Component 6 — Postman Collection

### Requests

| # | Name | Method | Path | Auth |
|---|------|--------|------|------|
| 1 | Get Access Token | `POST` | `/auth/token` | None |
| 2 | Get Current Weather | `GET` | `/weather?city=Hanoi&units=metric` | Bearer token |
| 3 | Get 5-day Forecast | `GET` | `/forecast?city=HoChiMinh&days=5&units=metric` | Bearer token |
| 4 | Health Check | `GET` | `/health` | None |
| 5 | Unauthorized Request | `GET` | `/weather?city=Hanoi` | No token (expect 401) |

### Variables (no hardcoded URLs or tokens)

```
base_url      = https://api.maxweather.com
client_id     = {{client_id}}
client_secret = {{client_secret}}
access_token  = (auto-set by Get Access Token request)
```

---

## Real AWS Test Results

All tests run against AWS Lab account `961341524524` (us-east-1, temporary 72h credentials). Resources destroyed after each test session.

### Test Session — 2026-04-25

#### terraform apply

```
terraform apply -auto-approve   # tests/real-aws/main.tf
Apply complete! Resources: 44 added, 0 changed, 0 destroyed.
```

#### KMS Module

| Check | Result | Detail |
|-------|--------|--------|
| 4 KMS keys created | ✅ Pass | aurora, elasticache, eks, s3 |
| Keys have correct IAM policy | ✅ Pass | root + CloudWatch Logs + SNS principals |
| Key aliases created | ✅ Pass | `alias/maxweather-awslab-{service}` |

**Bug discovered and fixed:** Real AWS rejects `CreateLogGroup` with `kms_key_id` when the KMS key policy does not explicitly grant `logs.{region}.amazonaws.com` the right to encrypt. LocalStack does not enforce this. Fix: added explicit `AllowCloudWatchLogs` statement with `kms:EncryptionContext:aws:logs:arn` condition.

#### VPC Module

| Check | Result | Detail |
|-------|--------|--------|
| VPC created | ✅ Pass | `vpc-0494be3d5fe328075`, CIDR `10.99.0.0/16` |
| 4 subnets across 2 AZs | ✅ Pass | 2 public + 2 private (us-east-1a, us-east-1b) |
| Internet Gateway attached | ✅ Pass | `igw-0a420f620d6cbe65f` |
| Route tables created | ✅ Pass | 1 public + 2 private route tables |
| NAT Gateway skipped | ✅ Pass | `enable_nat_gateway=false` for lab cost saving |

#### CloudWatch Module

| Check | Result | Detail |
|-------|--------|--------|
| 7 log groups created | ✅ Pass | app, eks, aurora, valkey/slow-log, valkey/engine-log, api-gateway, lambda/authorizer |
| All log groups KMS-encrypted | ✅ Pass | All use `key/7b7cd082` (eks key) |
| 6 CloudWatch alarms created | ✅ Pass | aurora-cpu, aurora-connections, valkey-cpu, valkey-memory, api-5xx, api-latency |
| SNS topic created | ✅ Pass | `arn:aws:sns:us-east-1:961341524524:maxweather-awslab-alerts` |
| Alarm states | ✅ Pass | OK (API alarms), INSUFFICIENT_DATA (RDS/ElastiCache — no actual infra) |

**Bug discovered and fixed:** CloudWatch dashboard widget `properties` must include `region` field — real AWS validates this, LocalStack does not. Fix: added `region = var.aws_region` to all 4 widget blocks.

#### ECR Module

| Check | Result | Detail |
|-------|--------|--------|
| Repository created | ✅ Pass | `961341524524.dkr.ecr.us-east-1.amazonaws.com/maxweather-awslab/weather-service` |
| Lifecycle policy applied | ✅ Pass | Max 30 tagged images, expire untagged after 1 day |

#### Lambda Authorizer Module

**Bug discovered and fixed (pre-apply):** Lambda environment variables cannot include `AWS_REGION` — it is a reserved key automatically injected by the Lambda runtime. Attempting to set it returns `InvalidParameterValueException`. Fix: removed `AWS_REGION` from the environment block; the Python handler already reads it from the runtime-injected variable.

**Bug discovered and fixed (post-apply):** Lambda role in the test environment had only `AWSLambdaBasicExecutionRole` (CloudWatch Logs only). DynamoDB `GetItem` was silently failing via `except ClientError: return False`. Fix: added `dynamodb:GetItem` policy and `kms:Decrypt` + `kms:GenerateDataKey` for the DynamoDB KMS key.

| Test | Input | Expected | Result |
|------|-------|----------|--------|
| Valid Bearer token | `Authorization: Bearer test-key-123` (active=true in DynamoDB) | IAM Allow policy | ✅ Pass |
| Invalid Bearer token | `Authorization: Bearer wrong-key` | `Unauthorized` exception | ✅ Pass |
| Missing Authorization header | `headers: {}` | `Unauthorized` exception | ✅ Pass |

**Valid key response:**
```json
{
  "principalId": "api-key",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{ "Action": "execute-api:Invoke", "Effect": "Allow", "Resource": "..." }]
  },
  "context": { "authorized": "true" }
}
```

#### terraform destroy

```
Destroy complete! Resources: 44 destroyed.
```

All resources cleaned up successfully.

---

## Architecture Compliance Audit

Cross-check between `design/architecture.md` and all source code. Performed 2026-04-25.

### Terraform — Parameter Compliance

| Parameter | Architecture Spec | Before Fix | After Fix | Status |
|-----------|------------------|------------|-----------|--------|
| `kubernetes_version` (staging) | 1.34 | 1.31 | **1.34** | ✅ Fixed |
| `kubernetes_version` (production) | 1.34 | 1.31 | **1.34** | ✅ Fixed |
| Production `az_count` | 3 (3 NAT GWs) | 2 | **3** | ✅ Fixed |
| Staging Aurora instance | `db.t4g.medium` | `db.r7g.large` | **`db.t4g.medium`** | ✅ Fixed |
| Staging Valkey node type | `cache.t4g.medium` | `cache.r7g.large` | **`cache.t4g.medium`** | ✅ Fixed |
| Production EKS burst type | `m7i.large` | `m7i.xlarge` | **`m7i.large`** | ✅ Fixed |
| Production EKS burst max | 7 ("0–7 nodes") | 6 | **7** | ✅ Fixed |
| Scheduled scaling schedules | 5 schedules | 2 schedules | **5 schedules** | ✅ Fixed |

### Kubernetes — Resource Sizing Compliance

| Resource | Architecture Spec | Before Fix | After Fix | Status |
|----------|------------------|------------|-----------|--------|
| KEDA `maxReplicaCount` | 20 | 10 | **20** | ✅ Fixed |
| KEDA weekday `desiredReplicas` | 12 | 6 | **12** | ✅ Fixed |
| KEDA weekday end time | 09:30 UTC+7 | 10:00 UTC+7 | **09:30 UTC+7** | ✅ Fixed |
| KEDA weekend trigger | exists (07:30–10:30, 7 pods) | missing | **added** | ✅ Fixed |
| HPA `maxReplicas` | 20 | 10 | **20** | ✅ Fixed |
| Staging pod CPU request | 100m | 250m | **100m** | ✅ Fixed |
| Staging pod RAM request | 128Mi | 256Mi | **128Mi** | ✅ Fixed |
| Production pod CPU request | 200m | 500m | **200m** | ✅ Fixed |
| Production HPA `maxReplicas` | 20 | 10 | **20** | ✅ Fixed |

### Components Not Fully Tested (require full EKS cluster)

| Component | Reason Not Tested | How to Verify |
|-----------|-------------------|---------------|
| IAM — IRSA | Requires live EKS OIDC provider | `kubectl exec` → `aws sts get-caller-identity` |
| Aurora | ~10min provisioning, high cost | Apply to staging, connect from private subnet |
| ElastiCache Valkey | Requires VPC private subnet | `redis-cli -h <endpoint> -p 6379` from pod |
| EKS node groups | ~15min provisioning | `kubectl get nodes` |
| KEDA ScaledObject | Requires EKS + KEDA installed | `kubectl get scaledobject` |
| Scheduled scaling | Requires ASG from EKS | Check ASG scheduled actions in AWS Console |
| Jenkins pipeline | Requires Jenkins EC2 | Run pipeline, verify each stage |

### Bugs Found and Fixed (all sessions)

| # | Bug | Discovered By | Fix |
|---|-----|---------------|-----|
| 1 | Aurora `monitoring_role_arn` used empty string default | Code review | Changed to internal `aws_iam_role.enhanced_monitoring.arn` |
| 2 | CloudWatch dashboard HCL used `;` as attribute separator | `terraform validate` | Split each attribute to its own line |
| 3 | Duplicate log group `/lambda/authorizer` created by both cloudwatch and lambda-authorizer modules | Code review | Removed `lambda_auth` from cloudwatch module |
| 4 | Dockerfile: `pip install --user` installs to `/root/.local` (inaccessible to non-root) | kind test | Switched to Python venv at `/opt/venv` |
| 5 | topologySpreadConstraints pods Pending in kind | kind test | Label kind worker nodes with `topology.kubernetes.io/zone` |
| 6 | CloudWatch dashboard widgets missing `region` field | Real AWS test | Added `region = var.aws_region` to all 4 widget blocks |
| 7 | KMS key policy missing CloudWatch Logs principal | Real AWS test | Added `AllowCloudWatchLogs` statement with service principal |
| 8 | Lambda env var `AWS_REGION` is reserved by Lambda runtime | Real AWS test | Removed from environment block; Lambda injects it automatically |
| 9 | Lambda role missing `dynamodb:GetItem` and KMS permissions | Real AWS test | Added inline policy to test role |
