# AWS ECS Template - Task Runner
# Usage: just <recipe> [args]

set positional-arguments := true
set dotenv-load := true

aws_region := "ap-northeast-1"
project_name := "myapp"
environment := "dev"

# Image tag: always use current git SHA
image_tag := `git rev-parse --short HEAD`

domain_name := env("DOMAIN_NAME", "example.com")

export AWS_PROFILE := env("AWS_PROFILE", "terraform")
export AWS_REGION := aws_region

# Show available recipes
default:
    @just --list

# --------------------------------------------------------------------------------
# Setup / Destroy
# --------------------------------------------------------------------------------

# Full setup: shared → project → build → deploy
setup: shared-apply-auto project-apply-auto build deploy
    @echo ""
    @echo "=== Setup Complete ==="
    @echo "User:  https://user.{{domain_name}}/health"
    @echo "Admin: https://admin.{{domain_name}}/health"

# Confirm destructive operation
_confirm-destroy:
    @echo "This will destroy ALL infrastructure and data."
    @read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ] || { echo "Aborted."; exit 1; }

# Full destroy: ECS → S3 → cache repos → project → shared
destroy: _confirm-destroy ecs-delete s3-empty ecr-delete-cache project-destroy shared-destroy
    @echo ""
    @echo "=== Destroy Complete ==="

# --------------------------------------------------------------------------------
# Terraform - Shared
# --------------------------------------------------------------------------------

# Init shared infrastructure
shared-init:
    terraform -chdir=terraform/shared/environments/{{environment}} init -upgrade

# Plan shared infrastructure
shared-plan: shared-init
    terraform -chdir=terraform/shared/environments/{{environment}} plan

# Apply shared infrastructure
shared-apply: shared-init
    terraform -chdir=terraform/shared/environments/{{environment}} apply

# Apply shared infrastructure (auto-approve)
shared-apply-auto: shared-init
    terraform -chdir=terraform/shared/environments/{{environment}} apply -auto-approve

# Destroy shared infrastructure
shared-destroy:
    terraform -chdir=terraform/shared/environments/{{environment}} destroy -auto-approve

# --------------------------------------------------------------------------------
# Terraform - Project
# --------------------------------------------------------------------------------

# Init project infrastructure
project-init:
    terraform -chdir=terraform/project/environments/{{environment}} init -upgrade

# Plan project infrastructure
project-plan: project-init
    terraform -chdir=terraform/project/environments/{{environment}} plan

# Apply project infrastructure
project-apply: project-init
    terraform -chdir=terraform/project/environments/{{environment}} apply

# Apply project infrastructure (auto-approve)
project-apply-auto: project-init
    terraform -chdir=terraform/project/environments/{{environment}} apply -auto-approve

# Destroy project infrastructure
project-destroy:
    terraform -chdir=terraform/project/environments/{{environment}} destroy -auto-approve

# --------------------------------------------------------------------------------
# Docker Build & Push
# --------------------------------------------------------------------------------

# ECR login
ecr-login:
    aws ecr get-login-password --region {{aws_region}} | \
        docker login --username AWS --password-stdin \
        "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.{{aws_region}}.amazonaws.com"

# Build and push a single app service (e.g., just build-one user-api)
build-one service: ecr-login
    #!/usr/bin/env bash
    set -euo pipefail
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.{{aws_region}}.amazonaws.com"
    IMAGE="${ECR_REGISTRY}/{{project_name}}-{{environment}}-{{service}}:{{image_tag}}"
    echo "--- Build: {{service}} ({{image_tag}}) ---"
    docker build --platform linux/amd64 -t "$IMAGE" "apps/{{service}}"
    docker push "$IMAGE"
    echo "Pushed $IMAGE"

# Build and push nginx sidecar
build-nginx: ecr-login
    #!/usr/bin/env bash
    set -euo pipefail
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.{{aws_region}}.amazonaws.com"
    IMAGE="${ECR_REGISTRY}/{{project_name}}-{{environment}}-nginx:{{image_tag}}"
    echo "--- Build: nginx ({{image_tag}}) ---"
    docker build --platform linux/amd64 -t "$IMAGE" "ecs/nginx"
    docker push "$IMAGE"
    echo "Pushed $IMAGE"

# Mirror aws-for-fluent-bit:init-latest to private ECR
# (Fargate private subnets can't pull from public.ecr.aws directly)
# fluent-bit ECR repo uses MUTABLE tags to allow init-latest overwrite.
mirror-fluent-bit: ecr-login
    #!/usr/bin/env bash
    set -euo pipefail
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.{{aws_region}}.amazonaws.com"
    SRC="public.ecr.aws/aws-observability/aws-for-fluent-bit:init-latest"
    DST="${ECR_REGISTRY}/{{project_name}}-{{environment}}-fluent-bit:init-latest"
    echo "--- Mirror: ${SRC} -> ${DST} ---"
    docker pull --platform linux/amd64 "$SRC"
    docker tag "$SRC" "$DST"
    docker push "$DST"
    echo "Mirrored to $DST"

# Build and push all images (apps + nginx), then save tag to .env
build: build-nginx (build-one "user-api") (build-one "admin-api")
    #!/usr/bin/env bash
    set -euo pipefail
    if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
        sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG={{image_tag}}/" .env && rm -f .env.bak
    else
        echo "IMAGE_TAG={{image_tag}}" >> .env
    fi
    echo "IMAGE_TAG={{image_tag}} saved to .env"

# --------------------------------------------------------------------------------
# ecspresso
# --------------------------------------------------------------------------------

# Deploy a single service (e.g., just deploy-one user-api)
deploy-one service:
    cd ecs/{{service}} && IMAGE_TAG={{image_tag}} NGINX_IMAGE_TAG={{image_tag}} ecspresso deploy

# Deploy all services
deploy: (deploy-one "user-api") (deploy-one "admin-api")

# Build, push, and deploy a single service (full flow)
ship service: build-nginx (build-one service) (deploy-one service)

# Build, push, and deploy all services
ship-all: build deploy

# Verify ecspresso config
verify service:
    cd ecs/{{service}} && ecspresso verify

# Verify all services
verify-all: (verify "user-api") (verify "admin-api")

# Render task/service definitions
render service:
    @echo "--- Task Definition ---"
    @cd ecs/{{service}} && IMAGE_TAG={{image_tag}} NGINX_IMAGE_TAG={{image_tag}} ecspresso render task-definition
    @echo ""
    @echo "--- Service Definition ---"
    @cd ecs/{{service}} && ecspresso render service-definition

# Show diff against running service
diff service:
    cd ecs/{{service}} && IMAGE_TAG={{image_tag}} NGINX_IMAGE_TAG={{image_tag}} ecspresso diff

# Rollback a service
rollback service:
    cd ecs/{{service}} && ecspresso rollback

# Scale a service (e.g., just scale user-api 2)
scale service count:
    cd ecs/{{service}} && ecspresso scale --tasks {{count}}

# ECS Exec into a service container
exec service:
    cd ecs/{{service}} && ecspresso exec --command /bin/sh

# --------------------------------------------------------------------------------
# Destroy helpers
# --------------------------------------------------------------------------------

# Delete all ECS services
ecs-delete:
    #!/usr/bin/env bash
    set -euo pipefail
    for service in user-api admin-api; do
        echo "--- Deleting $service ---"
        (cd "ecs/$service" && ecspresso delete --force --terminate) || true
    done

# Delete ECR pull-through cache repositories (auto-created, not Terraform-managed)
ecr-delete-cache:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "--- Deleting ECR pull-through cache repositories ---"
    repos=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `ecr-public/`)].repositoryName' --output text 2>/dev/null || true)
    for repo in $repos; do
        echo "  Deleting $repo"
        aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
    done
    echo "  done"

# Empty all S3 buckets (including versioned objects)
s3-empty:
    #!/usr/bin/env bash
    set -euo pipefail
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || { echo "ERROR: Failed to get account ID"; exit 1; }
    for bucket in \
        "{{project_name}}-{{environment}}-user-assets" \
        "{{project_name}}-{{environment}}-admin-assets" \
        "{{project_name}}-{{environment}}-access-logs-${ACCOUNT_ID}" \
        "{{project_name}}-{{environment}}-audit-logs-${ACCOUNT_ID}"; do
        echo "--- Emptying $bucket ---"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        python3 scripts/empty-versioned-bucket.py "$bucket"
        echo "  done"
    done

# --------------------------------------------------------------------------------
# Utility
# --------------------------------------------------------------------------------

# Check connectivity for all lanes
check:
    @echo "--- user ---"
    @curl -sf https://user.{{domain_name}}/health && echo ""
    @echo "--- admin ---"
    @curl -sf https://admin.{{domain_name}}/health && echo ""

# Generate CloudFront signing keypair
generate-signing-keypair:
    bash scripts/generate-signing-keypair.sh
