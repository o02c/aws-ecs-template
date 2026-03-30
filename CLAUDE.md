# CLAUDE.md - Project Conventions

## Architecture Overview

CloudFront → Internal ALB → ECS Fargate / S3 (static assets)

- Multiple traffic lanes (user, admin) sharing VPC, ECS Cluster, Aurora DB
- Per-lane resources: CloudFront distribution, ALB, S3 bucket
- ECS service deployment managed by ecspresso (not Terraform)
- CI/CD: S3 push → EventBridge → CodePipeline → CodeBuild → ecspresso deploy

### Multi-Project Architecture

- Single AWS account, multiple projects each with its own VPC
- Shared VPC provides egress (NAT Gateway) via Transit Gateway
- IAM users managed in shared state
- Project VPCs connect to shared VPC via TGW for internet access

```
[Project VPC] ----> [Transit Gateway] ----> [Shared VPC] ----> [NAT GW] ----> Internet
```

## Directory Structure

```
terraform/
  shared/                    # Shared infrastructure (1 per account)
    modules/
      network/               # Shared VPC, NAT GW, Transit Gateway
      iam/                   # IAM users, groups, policies
      kms/                   # Shared KMS keys
    environments/
      dev/                   # main.tf, locals.tf, variables.tf, etc.
      prod/

  project/                   # Project template (copy per project)
    modules/
      network/               # Project VPC, subnets, TGW attachment
      db/                    # Aurora PostgreSQL (Serverless v2)
      lb/                    # Internal ALB (per-lane)
      storage/               # S3 + CloudFront OAC (per-lane)
      app/                   # ECS cluster, ECR, IAM, logging
      cdn/                   # CloudFront distribution (per-lane)
      cicd/                  # CodePipeline, CodeBuild
      dns/                   # Route53, ACM
      dns_firewall/          # Route53 Resolver DNS Firewall
      kms/                   # Project KMS keys
      logging/               # Centralized logging
    environments/
      dev/                   # main.tf, locals.tf, variables.tf, etc.
      prod/

ecs/
  <service-name>/            # ecspresso config per service
```

### State Management

- Shared state: `shared/<env>/terraform.tfstate`
- Project state: `<project-name>/<env>/terraform.tfstate`
- Projects reference shared state via `terraform_remote_state`

## Naming Conventions

- Resource names: `<ProjectName>-<Environment>-<identifier>`
- Do NOT include AWS service names in identifiers (e.g., `myapp-prod-api` not `myapp-prod-ecs-api`)
- `main.tf` is only allowed in `environments/` directories
- Module files use concrete AWS service or resource names: `ecs_cluster.tf`, `aurora.tf`, `s3.tf`

## Tag Management

- Use AWS provider `default_tags` block to set ProjectName, Environment, ManagedBy
- Individual resources only add extra tags like Name
- Do NOT duplicate default tags on individual resources

## File Organization

- File names must clearly indicate contained resources
- Split when: >100 lines OR 3+ different resource types mixed
- Example splits: `vpc.tf` (VPC/IGW), `subnets.tf`, `nat_gateway.tf` (NAT GW/EIP), `route_tables.tf`

## Code Style

- Section comments:
```hcl
# --------------------------------------------------------------------------------
# Section Name
# --------------------------------------------------------------------------------
```
- Use `#` comments only (no `//`)
- `for_each` required, `count` prohibited (state path readability)
- Add outputs and variables only when needed, not for display

## Security Group Pattern

- `network` module creates empty SG shells (no inline ingress/egress)
- Each consuming module adds `aws_security_group_rule` resources
- ALB SGs are created per-lane via `for_each`

## Multiple Lanes Pattern

- Lanes (user, admin) defined as map in locals
- Per-lane modules called with `for_each = local.lanes`
- Shared resources: VPC, ECS cluster, Aurora DB
- Per-lane resources: ALB, CloudFront, S3

## Development Workflow

```bash
# Shared infrastructure (deploy first)
cd terraform/shared/environments/dev
terraform init
terraform plan
terraform apply

# Project infrastructure
cd terraform/project/environments/dev
terraform init
terraform plan
terraform apply
```

## ecspresso Conventions

- Config in `ecs/<service-name>/`
- Files: `ecspresso.yml`, `ecs-service-def.jsonnet`, `ecs-task-def.jsonnet`
- Use tfstate plugin to reference Terraform outputs
- Service/task definitions in Jsonnet format
