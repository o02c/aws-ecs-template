# Architecture

## Overview

Multi-lane web application infrastructure on AWS using ECS Fargate. Lanes share a
single CloudFront distribution and are split by path prefix (see
[path-routing-app-guide.md](path-routing-app-guide.md) for the app-side contract).

```
Internet
  │
  ▼
CloudFront (single distribution, path-routed)
  ├── /api/*       → user  ALB (VPC Origin) → ECS user-api
  ├── /admin/api/* → admin ALB (VPC Origin) → ECS admin-api
  ├── /admin*      → admin S3 (OAC)
  ├── /files/*     → user  S3 (OAC, signed URL)
  └── default      → user  S3 (OAC)
                     │
                     ▼
                 ECS Fargate (shared cluster)
                     │
                     ▼
                 Aurora PostgreSQL Serverless v2
```

## Components

### Network
- Single VPC with public/private subnets across 2 AZs
- NAT Gateway for outbound from private subnets
- Security groups created as empty shells in network module; rules added by consuming modules

### Load Balancer (per-lane)
- Internal ALB in private subnets
- Connected to CloudFront via VPC Origin
- HTTPS listener with ACM certificate

### Application
- ECS Cluster with Fargate + Fargate Spot capacity providers
- ECR repository per service
- Per-service IAM task roles with RDS IAM auth and S3 access
- CloudWatch log groups per service
- ECS services/tasks managed by ecspresso (not Terraform)

### Database
- Aurora PostgreSQL Serverless v2
- IAM database authentication enabled
- Shared across all lanes
- Bootstrap (one-time per env): `just db-bootstrap-app` creates the `app`
  PostgreSQL role with `rds_iam` so ECS tasks can connect via IAM auth. Tasks
  verify connectivity at gunicorn worker boot (`SELECT 1` via pg8000); result
  is reflected in `/api/test/db` and `scripts/verify-deploy.sh` step 10.

### CDN (single distribution, path-routed)
- 1 CloudFront distribution shared across lanes; path patterns select the origin
- Origins per lane (ALB via VPC Origin, S3 via OAC)
- CachingDisabled for ALB behaviors, custom static cache for S3 behaviors
- CloudFront Function (viewer-request) on S3 behaviors: trailing-slash → `index.html`,
  bare lane prefix → 301 to `<prefix>/`
- Optional WAF IP allowlist with `scope = "admin" | "global"` (see
  `terraform/project/modules/cdn/waf.tf`)

### Storage (per-lane)
- S3 bucket with versioning and encryption
- CloudFront OAC for secure access
- IAM policy for ECS task access (including presigned URLs)

### App Resources (shared bucket, lane-scoped via IAM)
- Single S3 bucket `${project}-${env}-app-resources` for startup config and
  report templates read by ECS tasks
- Internal use only (no CloudFront origin)
- Layout: `common/...` (shared across lanes), `<lane>/...` (lane-private)
- Lane isolation enforced by inline IAM policies on each task role:
  `GetObject` / `ListBucket` scoped to `common/*` + `<lane>/*`
- SSE-KMS (project `s3` key), versioning Enabled, noncurrent versions expire
  after 90 days, BucketOwnerEnforced (ACLs disabled)

### CI/CD
- Artifact S3 bucket with EventBridge notifications
- CodePipeline per service: Source (S3) → Build (CodeBuild) → Deploy (ecspresso)
- CodeBuild for Docker build + ECR push, and ecspresso deploy

## Security Group Flow

```
CloudFront → ALB SG (port 443, CloudFront prefix list)
ALB SG → ECS SG (container port)
ECS SG → DB SG (port 5432)
ECS SG → 0.0.0.0/0 (port 443, for ECR/CloudWatch/S3)
```

## Naming Convention

`<ProjectName>-<Environment>-<identifier>`

- No AWS service names in identifiers
- Tags managed via provider `default_tags`
