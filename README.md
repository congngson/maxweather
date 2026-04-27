# MaxWeather — DevOps Technical Assessment

## Table of Contents

- [Project Overview](#project-overview)
- [Design Overview](#design-overview)
- [Folder Structure](#folder-structure)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Environment Variables](#environment-variables)
- [Coding Standards](#coding-standards)
- [Component 1 — Application (weather-service)](#component-1--application-weather-service)
- [Component 2 — Terraform Infrastructure](#component-2--terraform-infrastructure)
- [Component 3 — Kubernetes Manifests](#component-3--kubernetes-manifests)
- [Component 4 — Jenkins Pipeline](#component-4--jenkins-pipeline)
- [Component 5 — API Gateway](#component-5--api-gateway)
- [Component 6 — Postman Collection & Live Demo](#component-6--postman-collection--live-demo)
- [Real AWS Test Results](#real-aws-test-results)


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
API Gateway's native API key mechanism offers no per-key revocation granularity and no audit trail. The Lambda Authorizer reads from DynamoDB on each request, enabling real-time key status checks (`active` flag), per-key access control, and a full CloudTrail audit trail. Latency overhead is absorbed by API Gateway's authorizer cache (TTL 300s).

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

### CI/CD Flow

```
git push
    ↓
Test → Build & Push to ECR (staging)
    ↓
Deploy Staging → Smoke Test        ← fail = stop, production never touched
    ↓
Manual Approval (ops-team, 30min)  ← human gate before any production change
    ↓
Promote Image → ECR (production)
    ↓
Deploy Production → Health Check
```

Same image tag flows from staging to production — no rebuild, no substitution. Staging smoke test failure blocks production entirely.

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
│   └── Jenkinsfile                      # Single pipeline: Test→Build→Staging→Approve→Production
│
├── postman/
│   └── MaxWeather.postman_collection.json
│
├── tests/
│   ├── real-aws/                        # Terraform test against real AWS (Lab account)
│   │   ├── main.tf                      # Full stack: VPC, EKS, Aurora, Valkey, Lambda, API GW
│   │   └── src/
│   │       └── weather.py               # Weather Lambda — proxies to OpenWeatherMap
│   └── demo/                            # Minimal free-tier demo (personal account, ap-southeast-1)
│       ├── main.tf                      # DynamoDB + Authorizer Lambda + Weather Lambda + API GW
│       ├── variables.tf
│       └── src/
│           ├── authorizer.py            # Lambda Authorizer
│           └── weather.py               # Weather Lambda
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

## Deployment Guide

Complete first-time deployment sequence. Subsequent deployments are handled by Jenkins automatically.

### Step 1 — Bootstrap Terraform Backend (one-time)

Create S3 bucket and DynamoDB lock table before the first `terraform init`:

```bash
aws s3 mb s3://maxweather-tfstate-<account-id> --region ap-southeast-1
aws s3api put-bucket-versioning \
  --bucket maxweather-tfstate-<account-id> \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name maxweather-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

### Step 2 — Deploy Infrastructure

```bash
ENV=staging   # or production
cd terraform/environments/${ENV}
terraform init
terraform apply -var-file="terraform.tfvars"
```

Modules deploy in dependency order automatically: `kms → iam → vpc → ecr → aurora → elasticache → eks → cloudwatch → lambda-authorizer → scheduled-scaling`.

### Step 3 — Populate Secrets Manager

```bash
REGION=ap-southeast-1

aws secretsmanager create-secret \
  --name "maxweather/${ENV}/openweathermap-api-key" \
  --secret-string "YOUR_OWM_API_KEY" \
  --region $REGION

aws secretsmanager create-secret \
  --name "maxweather/${ENV}/db-password" \
  --secret-string "YOUR_DB_PASSWORD" \
  --region $REGION
```

### Step 4 — Seed API Keys (DynamoDB)

```bash
aws dynamodb put-item \
  --table-name "maxweather-${ENV}-api-keys" \
  --item '{
    "api_key": {"S": "your-bearer-token"},
    "active":  {"BOOL": true},
    "client":  {"S": "client-name"}
  }' \
  --region $REGION
```

### Step 5 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --region $REGION \
  --name "maxweather-${ENV}"
```

### Step 6 — Install Cluster Add-ons (first time only)

```bash
# KEDA
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace

# Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -f k8s/nginx-ingress/values.yaml \
  --namespace ingress-nginx --create-namespace
```

### Step 7 — Build and Push Docker Image

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${ECR}/maxweather-${ENV}/weather-service"
TAG=$(git rev-parse --short HEAD)

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR

docker build -t ${IMAGE}:${TAG} app/
docker push ${IMAGE}:${TAG}
```

### Step 8 — Deploy to Kubernetes

```bash
kubectl apply -k k8s/overlays/${ENV}/
kubectl rollout status deployment/weather-service -n maxweather
```

### Step 9 — Configure API Gateway

See [Component 5 — API Gateway](#component-5--api-gateway).

### Step 10 — Set Up Jenkins

See [Component 4 — Jenkins Pipeline](#component-4--jenkins-pipeline). Jenkins handles all future deployments via the automated pipeline.

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

### Scheduled Scaling — 5 Schedules (UTC+7)

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

### Install Cluster Add-ons (first time only)

```bash
# KEDA — event-driven autoscaler (required for CronScaler + HTTP triggers)
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace

# Verify
kubectl get pods -n keda

# Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -f k8s/nginx-ingress/values.yaml \
  --namespace ingress-nginx --create-namespace
```

### Apply to Cluster

```bash
# Configure kubectl
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name maxweather-<env>

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

### Pipeline Flow

Single pipeline run — staging and production are **not** separate triggers. The same image that passes staging smoke test is promoted to production, guaranteeing no substitution between environments.

```
Checkout
    ↓
Test (unit tests)              ← fail = pipeline stops, no image built
    ↓
Build & Push → ECR (staging)   ← tagged: branch-sha-build#
    ↓
Deploy → Staging
    ↓
Smoke Test (staging)           ← fail = pipeline stops, production never touched
    ↓
Manual Approval Gate           ← ops-team approves, 30min timeout
    ↓
Promote Image → ECR (production)  ← re-tag same image, no rebuild
    ↓
Deploy → Production            ← rolling update: maxUnavailable=0, maxSurge=1
    ↓
Health Check (production)
```

### Key Behaviors

- Unit tests run before Docker build — fast fail saves build time
- Image tag: `{branch}-{git-sha}-{build#}` — unique, traceable, never `latest`
- Staging smoke test verifies `/health` (200) and `/weather` with Bearer token (200)
- **Promote Image stage**: re-tags the staging-tested image into the production ECR repo — same binary, no rebuild, no substitution risk
- Production rolling update: `maxUnavailable: 0`, `maxSurge: 1` — zero downtime, one pod at a time
- Failure at any stage triggers `kubectl rollout undo` on both environments
- Jenkins uses EC2 instance profile — no static AWS credentials stored

### Jenkins EC2 Setup (one-time)

Jenkins runs on a `t3.large` EC2 in the same VPC. SSH in and run:

```bash
# 1. Install Java + Jenkins
sudo apt update && sudo apt install -y openjdk-17-jdk
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install -y jenkins docker.io
sudo usermod -aG docker jenkins
sudo systemctl enable --now jenkins

# 2. Install kubectl and AWS CLI
# https://kubernetes.io/docs/tasks/tools/
# https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html

# 3. Configure kubeconfig (on the Jenkins EC2)
aws eks update-kubeconfig --region ap-southeast-1 --name maxweather-staging
aws eks update-kubeconfig --region ap-southeast-1 --name maxweather-production
```

**IAM permissions** — attach an instance profile to the EC2 with:
- `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`
- `eks:DescribeCluster`
- `sts:AssumeRole`

No static credentials stored — AWS SDK picks up the instance profile automatically.

**Required Jenkins plugins** (Manage Jenkins → Plugins → Available):
`Pipeline`, `Git`, `Amazon ECR`, `AWS Steps`, `Kubernetes CLI`

**Create pipeline job**: New Item → Pipeline → Pipeline script from SCM → Git → Script path: `jenkins/Jenkinsfile`

---

## Component 5 — API Gateway

### Setup (AWS Console)

1. Create **REST API** (not HTTP API — Lambda REQUEST authorizer requires REST API v1)
2. Integration: AWS_PROXY → Lambda (weather function)
3. Resources: `GET /health` (no auth) + `ANY /{proxy+}` (CUSTOM authorizer)
4. Attach **Lambda Authorizer** (REQUEST type) to `/{proxy+}` — cache TTL 300s
5. Set **throttling** — 1000 req/s (production), 100 req/s (staging)
6. Deploy to a named stage (`staging` / `production`)

### Lambda Authorizer Flow

```
API Gateway → Lambda → DynamoDB (GetItem by api_key)
                ↓
         active=true → IAM Allow policy (execute-api:Invoke)
         active=false or not found → raise Exception("Unauthorized") → 401
```

The authorizer reads `Authorization: Bearer <token>` from the HTTP header and looks up the key in the `maxweather-{env}-api-keys` DynamoDB table. Token is matched against the `api_key` partition key, and `active` boolean attribute is checked.

### API Key Management (DynamoDB)

```bash
# Add a new key
aws dynamodb put-item \
  --table-name maxweather-staging-api-keys \
  --item '{"api_key": {"S": "new-token"}, "active": {"BOOL": true}, "client": {"S": "client-name"}}'

# Revoke a key (set active=false — takes effect within authorizer cache TTL: 300s)
aws dynamodb update-item \
  --table-name maxweather-staging-api-keys \
  --key '{"api_key": {"S": "token-to-revoke"}}' \
  --update-expression "SET active = :v" \
  --expression-attribute-values '{":v": {"BOOL": false}}'

# List all keys
aws dynamodb scan --table-name maxweather-staging-api-keys \
  --projection-expression "api_key, active, client"
```

---

## Component 6 — Postman Collection & Live Demo

### Live Demo Endpoint

| Field | Value |
|-------|-------|
| Base URL | `https://7zyfi66dtj.execute-api.ap-southeast-1.amazonaws.com/demo` |
| API Key | `demo-key-maxweather-2026` |
| Region | ap-southeast-1 (Singapore) — permanent, free-tier |
| Stack | Lambda + DynamoDB + API Gateway REST (`tests/demo/`) |

```bash
# Health check — no auth required
curl https://7zyfi66dtj.execute-api.ap-southeast-1.amazonaws.com/demo/health

# Current weather
curl -H "Authorization: Bearer demo-key-maxweather-2026" \
  "https://7zyfi66dtj.execute-api.ap-southeast-1.amazonaws.com/demo/weather?city=Singapore"

# Forecast
curl -H "Authorization: Bearer demo-key-maxweather-2026" \
  "https://7zyfi66dtj.execute-api.ap-southeast-1.amazonaws.com/demo/forecast?city=Hanoi&days=3"

# No token — expect 401
curl "https://7zyfi66dtj.execute-api.ap-southeast-1.amazonaws.com/demo/weather?city=Singapore"
```

### Postman Collection

Collection file: `postman/MaxWeather.postman_collection.json`

Import into Postman — `base_url` and `api_key` are pre-filled to the live demo endpoint above. No manual setup required.

| # | Name | Method | Path | Auth | Expected |
|---|------|--------|------|------|----------|
| 1 | Health Check | `GET` | `/health` | None | `200 {"status":"healthy"}` |
| 2 | Get Current Weather — Singapore (metric) | `GET` | `/weather?city=Singapore&units=metric` | Bearer | `200` + OWM data |
| 3 | Get Current Weather — Hanoi (imperial) | `GET` | `/weather?city=Hanoi&units=imperial` | Bearer | `200` + OWM data |
| 4 | Get 5-day Forecast — Singapore | `GET` | `/forecast?city=Singapore&days=5&units=metric` | Bearer | `200` + forecast list |
| 5 | Unauthorized — no token | `GET` | `/weather?city=Singapore` | None | `401` |
| 6 | Forbidden — invalid token | `GET` | `/weather?city=Singapore` | Bearer (wrong) | `403` |

Each request includes automated test scripts verifying status codes, response envelope (`status`, `source`, `data`), and OWM data fields.

---

## Real AWS Test Results

### API Endpoint Verification — 2026-04-27

End-to-end tests against the demo stack (`tests/demo/`, account `618788620436`, ap-southeast-1).

| Test | Command | Expected | Result |
|------|---------|----------|--------|
| Health (no auth) | `GET /health` | `200 {"status":"healthy"}` | ✅ Pass |
| Weather with valid token | `GET /weather?city=Singapore` + Bearer | `200` + OWM data | ✅ Pass |
| Forecast with valid token | `GET /forecast?city=Hanoi&days=3` + Bearer | `200` + OWM data | ✅ Pass |
| No token | `GET /weather?city=Singapore` (no header) | `401 Unauthorized` | ✅ Pass |
| Wrong token | `GET /weather?city=Singapore` + wrong Bearer | `403 Forbidden` | ✅ Pass |

Sample response — `/weather?city=Singapore`:
```json
{
  "status": "success",
  "cached": false,
  "source": "OpenWeatherMap",
  "data": {
    "name": "Singapore",
    "main": { "temp": 29.5, "feels_like": 33.1, "humidity": 78 },
    "weather": [{ "description": "few clouds" }],
    "wind": { "speed": 3.2 },
    "cod": 200
  }
}
```

---

### Terraform Module Tests — 2026-04-25

All tests run against AWS Lab account `961341524524` (us-east-1, temporary 72h credentials). Resources destroyed after each test session.

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

