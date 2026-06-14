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

# Full setup: shared → project → secrets → build → deploy → health check
setup:
    DOMAIN_NAME={{domain_name}} bash scripts/full-deploy.sh

# Confirm destructive operation
_confirm-destroy:
    @echo "This will destroy ALL infrastructure and data."
    @read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ] || { echo "Aborted."; exit 1; }

# Full destroy: ECS → S3 → cache repos → project → shared → log cleanup
destroy: _confirm-destroy
    bash scripts/full-destroy.sh

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

# Destroy shared infrastructure (+ orphan VPC flow log group cleanup)
shared-destroy:
    terraform -chdir=terraform/shared/environments/{{environment}} destroy -auto-approve -refresh=false
    -aws logs delete-log-group --log-group-name "/aws/vpc/flow-log/shared-{{environment}}" 2>/dev/null || true

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

# Destroy project infrastructure (+ orphan log group cleanup)
project-destroy:
    terraform -chdir=terraform/project/environments/{{environment}} destroy -auto-approve
    -aws logs delete-log-group --log-group-name "/aws/vpc/flow-log/{{project_name}}-{{environment}}" 2>/dev/null || true
    -for svc in user-api admin-api; do aws logs delete-log-group --log-group-name "/ecs/{{project_name}}-{{environment}}/$svc" 2>/dev/null || true; done
    -aws logs delete-log-group --region us-east-1 --log-group-name "aws-waf-logs-{{project_name}}-{{environment}}" 2>/dev/null || true

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
    docker build --platform linux/amd64 -t "$IMAGE" "apps/nginx"
    docker push "$IMAGE"
    echo "Pushed $IMAGE"

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
        "{{project_name}}-{{environment}}-athena-results-${ACCOUNT_ID}" \
        "{{project_name}}-{{environment}}-db-sql-${ACCOUNT_ID}" \
        "aws-waf-logs-{{project_name}}-{{environment}}-${ACCOUNT_ID}"; do
        echo "--- Emptying $bucket ---"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        python3 scripts/empty-versioned-bucket.py "$bucket"
        echo "  done"
    done

# --------------------------------------------------------------------------------
# Utility
# --------------------------------------------------------------------------------

# Enable Object Lock on assets buckets (backup → recreate → restore → verify).
# Destructive: replaces each <lane>-assets bucket. Pass YES=1 to skip the prompt.
migrate-assets-object-lock:
    DOMAIN_NAME={{domain_name}} bash scripts/migrate-assets-object-lock.sh

# --------------------------------------------------------------------------------
# DB SQL Runner (out-of-band SQL via Lambda)
# --------------------------------------------------------------------------------
# Two Lambdas are deployed by module.db_sql:
#   - {{project_name}}-{{environment}}-db-sql-ddl  (master user via Secrets Manager)
#   - {{project_name}}-{{environment}}-db-sql-dml  (RDS IAM auth as dml_username)
#
# Initial bootstrap (run once after first project-apply):
#   - DML Lambda role (db_sql IAM auth target):
#       just db-sql-ddl "CREATE ROLE app_rw LOGIN; GRANT rds_iam TO app_rw; \
#                        GRANT CONNECT ON DATABASE app TO app_rw; \
#                        GRANT USAGE, CREATE ON SCHEMA public TO app_rw;"
#   - ECS task IAM auth role (matches db_config.iam_username = "app"):
#       just db-bootstrap-app
#
# Long SQL: stage to S3 then invoke with the key:
#   aws s3 cp ./patch.sql s3://<bucket>/ddl/2026-05-19-patch.sql
#   just db-sql-ddl-file ddl/2026-05-19-patch.sql

_db-sql-invoke fn payload:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(mktemp)
    payload_file=$(mktemp)
    trap 'rm -f "$out" "$payload_file"' EXIT
    printf '%s' {{ quote(payload) }} > "$payload_file"
    aws lambda invoke \
        --function-name "{{fn}}" \
        --cli-binary-format raw-in-base64-out \
        --payload "fileb://$payload_file" \
        --log-type Tail \
        --query 'LogResult' --output text "$out" \
        | base64 -d
    echo "--- response ---"
    cat "$out"
    echo ""

# Run inline DDL via the master-user Lambda
db-sql-ddl sql:
    @just _db-sql-invoke "{{project_name}}-{{environment}}-db-sql-ddl" \
        "$(jq -nc --arg sql '{{sql}}' '{sql:$sql}')"

# Run DDL from an S3 file (key must start with ddl/)
db-sql-ddl-file key:
    @just _db-sql-invoke "{{project_name}}-{{environment}}-db-sql-ddl" \
        "$(jq -nc --arg k '{{key}}' '{s3_key:$k}')"

# Run inline DML via the IAM-auth Lambda (pass fetch=true to return rows)
db-sql-dml sql fetch="false":
    @just _db-sql-invoke "{{project_name}}-{{environment}}-db-sql-dml" \
        "$(jq -nc --arg sql '{{sql}}' --argjson f {{fetch}} '{sql:$sql, fetch:$f}')"

# Run DML from an S3 file (key must start with dml/)
db-sql-dml-file key fetch="false":
    @just _db-sql-invoke "{{project_name}}-{{environment}}-db-sql-dml" \
        "$(jq -nc --arg k '{{key}}' --argjson f {{fetch}} '{s3_key:$k, fetch:$f}')"

# Bootstrap the ECS-app IAM role in PostgreSQL (idempotent).
# Matches db_config.iam_username = "app". rds-db:connect on this dbuser is
# already granted to every task role via module.db.rds_iam_auth_policy_arn.
# Re-runnable; CREATE ROLE is gated on pg_roles, GRANTs are no-ops if already set.
db-bootstrap-app:
    #!/usr/bin/env bash
    set -euo pipefail
    sql=$(cat <<'SQL'
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app') THEN
        CREATE ROLE app LOGIN;
      END IF;
    END
    $$;
    GRANT rds_iam TO app;
    GRANT CONNECT ON DATABASE app TO app;
    GRANT USAGE ON SCHEMA public TO app;
    SQL
    )
    payload=$(jq -nc --arg s "$sql" '{sql:$s}')
    just _db-sql-invoke "{{project_name}}-{{environment}}-db-sql-ddl" "$payload"

# --------------------------------------------------------------------------------
# Athena (access-log analysis)
# --------------------------------------------------------------------------------

# Create the CloudFront partitioned table (idempotent).
athena-create-cf-table:
    bash scripts/athena-query.sh athena/cloudfront/01_create_table.sql

# Create the ECS app-container partitioned table (idempotent).
athena-create-ecs-app-table:
    bash scripts/athena-query.sh athena/ecs-app/01_create_table.sql

# Create the ECS nginx-sidecar partitioned table (idempotent).
athena-create-ecs-nginx-table:
    bash scripts/athena-query.sh athena/ecs-nginx/01_create_table.sql

# Create the audit-log partitioned table (idempotent).
athena-create-audit-table:
    bash scripts/athena-query.sh athena/audit/01_create_table.sql

# Create the JST-companion views (idempotent — CREATE OR REPLACE).
athena-create-ecs-views:
    bash scripts/athena-query.sh athena/ecs-app/03_create_view_jst.sql
    bash scripts/athena-query.sh athena/ecs-nginx/03_create_view_jst.sql

# Run a saved query file. Pass DIST=EXXXXXXXX (or pull it from terraform output).
# Example: just athena-cf athena/cloudfront/02_sample_queries.sql DIST=E1ABC...
athena-cf sql dist="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{dist}}" ]]; then
        dist=$(terraform -chdir=terraform/project/environments/{{environment}} \
            output -raw cloudfront_distribution_id)
    else
        dist="{{dist}}"
    fi
    bash scripts/athena-query.sh -e "distributionid=${dist}" "{{sql}}"

# Simple HTTPS health check (both lanes, single domain with path prefix)
check:
    @echo "--- user ---"
    @curl -sf https://{{domain_name}}/api/health && echo ""
    @echo "--- admin ---"
    @curl -sf https://{{domain_name}}/admin/api/health && echo ""

# Full verify: HTTPS, TLS, every log destination, bucket posture
verify-deploy:
    bash scripts/verify-deploy.sh

# Generate CloudFront signing keypair
generate-signing-keypair:
    bash scripts/generate-signing-keypair.sh
