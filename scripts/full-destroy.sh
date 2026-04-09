#!/usr/bin/env bash
# Full destroy script: ECS → S3 → ECR cache → project → shared
# Usage: bash scripts/full-destroy.sh
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="ap-northeast-1"

PROJECT_NAME="myapp"
ENVIRONMENT="dev"

echo "=== Full Destroy: ${PROJECT_NAME}-${ENVIRONMENT} ==="

# --------------------------------------------------------------------------------
# 1. Delete ECS Services
# --------------------------------------------------------------------------------
echo ""
echo "--- [1/5] Delete ECS Services ---"
for service in user-api admin-api; do
  echo "  Deleting ${service}..."
  (cd "ecs/${service}" && ecspresso delete --force --terminate 2>&1 | tail -1) || true
done

# Wait for services to drain
echo "  Waiting for services to drain..."
for service in user-api admin-api; do
  while [ "$(aws ecs describe-services --cluster ${PROJECT_NAME}-${ENVIRONMENT} --services ${service} --query 'services[0].status' --output text 2>/dev/null)" = "DRAINING" ]; do
    sleep 5
  done
done
echo "  done"

# --------------------------------------------------------------------------------
# 2. Empty S3 Buckets
# --------------------------------------------------------------------------------
echo ""
echo "--- [2/5] Empty S3 Buckets ---"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SHARED_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
for bucket in \
  "${SHARED_PREFIX}-user-assets" \
  "${SHARED_PREFIX}-admin-assets" \
  "${SHARED_PREFIX}-access-logs-${ACCOUNT_ID}" \
  "${SHARED_PREFIX}-audit-logs-${ACCOUNT_ID}" \
  "${SHARED_PREFIX}-access-logs"; do
  echo "  Emptying ${bucket}..."
  aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
  python3 scripts/empty-versioned-bucket.py "${bucket}" 2>/dev/null || true
done

# --------------------------------------------------------------------------------
# 3. Delete ECR Pull-through Cache Repos
# --------------------------------------------------------------------------------
echo ""
echo "--- [3/5] Delete ECR Cache Repos ---"
repos=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `ecr-public/`)].repositoryName' --output text 2>/dev/null || true)
for repo in $repos; do
  echo "  Deleting ${repo}"
  aws ecr delete-repository --repository-name "${repo}" --force 2>/dev/null || true
done

# --------------------------------------------------------------------------------
# 4. Destroy Project Infrastructure
# --------------------------------------------------------------------------------
echo ""
echo "--- [4/5] Destroy Project Infrastructure ---"
terraform -chdir=terraform/project/environments/${ENVIRONMENT} init -upgrade -input=false
terraform -chdir=terraform/project/environments/${ENVIRONMENT} destroy -auto-approve -input=false

# --------------------------------------------------------------------------------
# 5. Destroy Shared Infrastructure
# --------------------------------------------------------------------------------
echo ""
echo "--- [5/5] Destroy Shared Infrastructure ---"
terraform -chdir=terraform/shared/environments/${ENVIRONMENT} init -upgrade -input=false
terraform -chdir=terraform/shared/environments/${ENVIRONMENT} destroy -auto-approve -input=false

# --------------------------------------------------------------------------------
# 6. Cleanup orphaned CloudWatch Log Groups
# --------------------------------------------------------------------------------
echo ""
echo "--- [6/6] Cleanup Log Groups ---"
for lg in \
  "/aws/vpc/flow-log/${PROJECT_NAME}-${ENVIRONMENT}-shared" \
  "/aws/vpc/flow-log/${PROJECT_NAME}-${ENVIRONMENT}" \
  "/ecs/${PROJECT_NAME}-${ENVIRONMENT}/admin-api" \
  "/ecs/${PROJECT_NAME}-${ENVIRONMENT}/user-api"; do
  aws logs delete-log-group --log-group-name "${lg}" 2>/dev/null && echo "  Deleted ${lg}" || true
done
# WAF logs (us-east-1)
for lane in user admin; do
  aws logs delete-log-group --log-group-name "aws-waf-logs-${PROJECT_NAME}-${ENVIRONMENT}-${lane}" --region us-east-1 2>/dev/null && echo "  Deleted aws-waf-logs-${PROJECT_NAME}-${ENVIRONMENT}-${lane}" || true
done

echo ""
echo "=== Destroy Complete ==="
