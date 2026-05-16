#!/usr/bin/env bash
set -euo pipefail

# Deploy all apps: Docker build+push, ecspresso deploy, frontend upload
# Usage: ./scripts/deploy.sh [user-api|admin-api|frontend]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
TARGET="${1:-all}"

SERVICES=("user-api" "admin-api")
LANES=("user" "admin")
PROJECT_NAME="myapp"
ENVIRONMENT="dev"

# --------------------------------------------------------------------------------
# ECR Login
# --------------------------------------------------------------------------------
ecr_login() {
  echo "--- ECR Login ---"
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
}

# --------------------------------------------------------------------------------
# Build & Push Docker Image
# --------------------------------------------------------------------------------
deploy_backend() {
  local service="$1"
  local repo="$PROJECT_NAME-$ENVIRONMENT-$service"
  local image="$ECR_REGISTRY/$repo:latest"

  echo "--- Build & Push: $service ---"
  docker build --platform linux/amd64 -t "$image" "$PROJECT_ROOT/apps/$service"
  docker push "$image"

  echo "--- ecspresso deploy: $service ---"
  cd "$PROJECT_ROOT/ecs/$service"
  ecspresso deploy --config ecspresso.yml
}

# --------------------------------------------------------------------------------
# Upload App Resources (startup config + report templates)
# --------------------------------------------------------------------------------
# Repo-managed templates land in s3://${PROJECT_NAME}-${ENVIRONMENT}-app-resources.
# Lane access is enforced by per-task-role IAM (see app/iam.tf), so we can
# sync everything in one call — IAM does the partitioning at read time.
deploy_app_resources() {
  local bucket="$PROJECT_NAME-$ENVIRONMENT-app-resources"
  echo "--- Upload app-resources (s3://${bucket}) ---"
  aws s3 sync "$PROJECT_ROOT/app-resources/" "s3://$bucket/" \
    --delete --exclude ".*" --exclude "README.md"
}

# --------------------------------------------------------------------------------
# Upload Frontend
# --------------------------------------------------------------------------------
# Path-routing: each lane's frontend is uploaded under its CloudFront path_prefix
# so that https://<domain><path_prefix>/index.html resolves directly. The default
# lane (user) lives at the bucket root so `default_root_object = "index.html"`
# serves https://<domain>/ . Non-default lanes use their prefix as the S3 key.
deploy_frontend() {
  local lane="$1"
  local bucket="$PROJECT_NAME-$ENVIRONMENT-$lane-assets"
  local s3_prefix=""
  if [ "$lane" != "user" ]; then
    s3_prefix="${lane}/"
  fi

  echo "--- Upload frontend: $lane (s3://${bucket}/${s3_prefix}) ---"
  aws s3 sync "$PROJECT_ROOT/apps/$lane-frontend/" "s3://$bucket/$s3_prefix" \
    --delete --exclude ".*"
}

# --------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------
case "$TARGET" in
  user-api|admin-api)
    ecr_login
    deploy_backend "$TARGET"
    ;;
  frontend)
    for lane in "${LANES[@]}"; do
      deploy_frontend "$lane"
    done
    ;;
  app-resources)
    deploy_app_resources
    ;;
  all)
    ecr_login
    for service in "${SERVICES[@]}"; do
      deploy_backend "$service"
    done
    for lane in "${LANES[@]}"; do
      deploy_frontend "$lane"
    done
    deploy_app_resources
    echo ""
    echo "=== Deploy Complete ==="
    echo "User:  https://o2c.click/api/health"
    echo "Admin: https://o2c.click/admin/api/health"
    ;;
  *)
    echo "Usage: $0 [user-api|admin-api|frontend|app-resources|all]"
    exit 1
    ;;
esac
