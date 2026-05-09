#!/usr/bin/env bash
# Full deployment script: shared → project → SSM secrets → build → deploy
# Usage: bash scripts/full-deploy.sh
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="ap-northeast-1"

PROJECT_NAME="myapp"
ENVIRONMENT="dev"
IMAGE_TAG=$(git rev-parse --short HEAD)

echo "=== Full Deploy: ${PROJECT_NAME}-${ENVIRONMENT} (${IMAGE_TAG}) ==="

# --------------------------------------------------------------------------------
# 1. Shared Infrastructure
# --------------------------------------------------------------------------------
echo ""
echo "--- [1/6] Shared Infrastructure ---"
terraform -chdir=terraform/shared/environments/${ENVIRONMENT} init -upgrade -input=false
terraform -chdir=terraform/shared/environments/${ENVIRONMENT} apply -auto-approve -input=false

# --------------------------------------------------------------------------------
# 2. Project Infrastructure
# --------------------------------------------------------------------------------
echo ""
echo "--- [2/6] Project Infrastructure ---"
terraform -chdir=terraform/project/environments/${ENVIRONMENT} init -upgrade -input=false
terraform -chdir=terraform/project/environments/${ENVIRONMENT} apply -auto-approve -input=false

# --------------------------------------------------------------------------------
# 3. SSM Parameter Store Secrets
# --------------------------------------------------------------------------------
echo ""
echo "--- [3/6] SSM Parameter Store Secrets ---"
for service in admin-api user-api; do
  PARAM_NAME="/${PROJECT_NAME}/${ENVIRONMENT}/${service}/django-secret-key"
  # Only set if current value is placeholder
  CURRENT=$(aws ssm get-parameter --name "${PARAM_NAME}" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  if [ "${CURRENT}" = "change-me" ] || [ -z "${CURRENT}" ]; then
    SECRET=$(openssl rand -hex 32)
    aws ssm put-parameter --name "${PARAM_NAME}" --value "${SECRET}" --type SecureString --overwrite --output text --query Version
    echo "  ${service}: set new secret (version $(aws ssm get-parameter --name "${PARAM_NAME}" --query 'Parameter.Version' --output text))"
  else
    echo "  ${service}: already set, skipping"
  fi
done

# --------------------------------------------------------------------------------
# 4. Docker Build & Push
# --------------------------------------------------------------------------------
echo ""
echo "--- [4/6] Docker Build & Push ---"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Build and push nginx
NGINX_IMAGE="${ECR_REGISTRY}/${PROJECT_NAME}-${ENVIRONMENT}-nginx:${IMAGE_TAG}"
echo "  Building nginx..."
docker build --platform linux/amd64 -t "${NGINX_IMAGE}" ecs/nginx
docker push "${NGINX_IMAGE}"

# Build and push app services
for service in user-api admin-api; do
  APP_IMAGE="${ECR_REGISTRY}/${PROJECT_NAME}-${ENVIRONMENT}-${service}:${IMAGE_TAG}"
  echo "  Building ${service}..."
  docker build --platform linux/amd64 -t "${APP_IMAGE}" "apps/${service}"
  docker push "${APP_IMAGE}"
done

# fluent-bit init image is served via ECR pull-through cache (auto-cached on
# first pull from public.ecr.aws). No manual mirror step required.

# Save image tag
if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
  sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=${IMAGE_TAG}/" .env && rm -f .env.bak
else
  echo "IMAGE_TAG=${IMAGE_TAG}" >> .env
fi

# --------------------------------------------------------------------------------
# 5. ECS Deploy
# --------------------------------------------------------------------------------
echo ""
echo "--- [5/6] ECS Deploy ---"
for service in admin-api user-api; do
  echo "  Deploying ${service}..."
  (cd "ecs/${service}" && IMAGE_TAG=${IMAGE_TAG} NGINX_IMAGE_TAG=${IMAGE_TAG} ecspresso deploy)
done

# --------------------------------------------------------------------------------
# 6. Health Check
# --------------------------------------------------------------------------------
echo ""
echo "--- [6/6] Health Check ---"
HEALTH_FAILED=0
echo "  Waiting 30s for services to stabilize..."
sleep 30
# Read per-lane hostnames from terraform output (apex / subdomain decision lives in locals.lanes).
LANE_DOMAINS_JSON=$(terraform -chdir=terraform/project/environments/dev output -json lane_domains)
for lane in $(echo "${LANE_DOMAINS_JSON}" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).keys()))'); do
  HOST=$(echo "${LANE_DOMAINS_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['${lane}'])")
  URL="https://${HOST}/health"
  echo -n "  ${lane}: ${URL} → "
  if curl -sf --max-time 10 "${URL}"; then
    echo " OK"
  else
    echo " FAILED"
    HEALTH_FAILED=1
  fi
done

echo ""
if [ "${HEALTH_FAILED}" -eq 1 ]; then
  echo "=== Deploy Complete (with health check failures) ==="
  exit 1
else
  echo "=== Deploy Complete ==="
fi
