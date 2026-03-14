# Architecture

## Overview

Multi-lane web application infrastructure on AWS using ECS Fargate.

```
Internet
  │
  ▼
CloudFront (per-lane)
  ├── /assets/*  → S3 (OAC)
  └── /*         → Internal ALB (VPC Origin)
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

### CDN (per-lane)
- CloudFront distribution with VPC origin (ALB) and S3 origin (OAC)
- Separate cache policies for API (no cache) and static assets

### Storage (per-lane)
- S3 bucket with versioning and encryption
- CloudFront OAC for secure access
- IAM policy for ECS task access (including presigned URLs)

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
