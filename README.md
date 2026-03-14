# AWS ECS Template

Terraform IaC template for multi-lane ECS Fargate applications with CloudFront, Aurora PostgreSQL, and CI/CD pipeline.

## Architecture

```
CloudFront → Internal ALB → ECS Fargate (per-lane)
CloudFront → S3 (static assets, per-lane)
ECS → Aurora PostgreSQL Serverless v2 (shared)
S3 artifact push → EventBridge → CodePipeline → CodeBuild → ecspresso deploy
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured
- ecspresso (for ECS service deployment)

## Directory Structure

```
terraform/
  environments/dev/     # Environment-specific configuration
  modules/
    network/            # VPC, subnets, route tables, security groups
    db/                 # Aurora PostgreSQL (Serverless v2)
    lb/                 # Internal ALB (per-lane)
    storage/            # S3 buckets + CloudFront OAC (per-lane)
    app/                # ECS cluster, ECR, IAM, logging
    cdn/                # CloudFront distributions (per-lane)
    cicd/               # CodePipeline, CodeBuild
ecs/
  user-api/             # ecspresso config for user API
  admin-api/            # ecspresso config for admin API
```

## Setup

1. Copy secret variables template:
   ```bash
   cd terraform/environments/dev
   cp secret.auto.tfvars.example secret.auto.tfvars
   # Edit secret.auto.tfvars with actual values
   ```

2. Initialize and deploy:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. Deploy ECS services:
   ```bash
   cd ecs/user-api
   ecspresso deploy
   ```

## Traffic Lanes

This template supports multiple traffic lanes (user, admin) with:
- **Shared**: VPC, ECS Cluster, Aurora DB
- **Per-lane**: CloudFront, ALB, S3 bucket

## CI/CD Flow

1. Push artifact to S3 (`s3://<project>-<env>-artifact/<service>/source.zip`)
2. EventBridge triggers CodePipeline
3. CodeBuild builds Docker image and pushes to ECR
4. CodeBuild deploys via ecspresso
