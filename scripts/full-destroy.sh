#!/usr/bin/env bash
# Full destroy: ECS → S3 empty → ECR cache → project TF (retry+empty) → shared TF → log cleanup
# Usage: bash scripts/full-destroy.sh
#
# Resource discovery is tag-based (ManagedBy=terraform) so this script does NOT
# need to be updated when resource names or prefixes change. The only hardcoded
# parts are:
#   - ECS cluster / service names (ecspresso owns those, not TF tags)
#   - ECR pull-through cache prefix (AWS auto-creates those, not TF-tagged)
#   - CloudWatch log group name patterns (AWS auto-creates flow log / ECS exec groups)
#
# Bucket race handling:
#   Terraform resources (aws_s3_bucket) intentionally do NOT set force_destroy.
#   Instead, this script runs `terraform destroy` in a retry loop that re-empties
#   any tag-matched buckets between attempts. This avoids the risk of
#   force_destroy accidentally deleting business data in prod.
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="ap-northeast-1"

PROJECT_NAME="myapp"
ENVIRONMENT="dev"

TF_DESTROY_MAX_ATTEMPTS="${TF_DESTROY_MAX_ATTEMPTS:-4}"

# --------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------

# List S3 buckets tagged ManagedBy=terraform in current account.
list_tagged_buckets() {
  local region="${1:-$AWS_REGION}"
  aws resourcegroupstaggingapi get-resources \
    --region "$region" \
    --tag-filters "Key=ManagedBy,Values=terraform" \
    --resource-type-filters "s3" \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output text 2>/dev/null \
    | tr '\t' '\n' \
    | awk -F: '{print $NF}' \
    | sort -u
}

# Pre-destroy: silence alerts before anything starts deleting. Emptying versioned
# buckets fires thousands of S3 ObjectRemoved events (-> s3-events SNS -> email),
# and tearing resources down trips CloudWatch alarms. Clear bucket notification
# configs and disable alarm actions FIRST so the teardown stays quiet. Both are
# best-effort (the resources get destroyed by terraform afterwards anyway).
disable_alerts() {
  local region="${1:-$AWS_REGION}"
  local buckets
  buckets="$(list_tagged_buckets "$region" || true)"
  while IFS= read -r bucket; do
    [ -z "$bucket" ] && continue
    aws s3api put-bucket-notification-configuration \
      --bucket "$bucket" --notification-configuration '{}' 2>/dev/null \
      && echo "  cleared S3 notifications: ${bucket}" || true
  done <<< "$buckets"

  local alarms
  alarms="$(aws cloudwatch describe-alarms --region "$region" \
    --alarm-name-prefix "${PROJECT_NAME}-${ENVIRONMENT}-" \
    --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || true)"
  if [ -n "$alarms" ]; then
    # shellcheck disable=SC2086  # word-split the name list into separate args
    aws cloudwatch disable-alarm-actions --region "$region" --alarm-names $alarms 2>/dev/null \
      && echo "  disabled CloudWatch alarm actions" || true
  fi
}

# Empty every TF-tagged bucket, including versioned objects.
empty_tagged_buckets() {
  local region="${1:-$AWS_REGION}"
  local buckets
  buckets="$(list_tagged_buckets "$region" || true)"
  if [ -z "$buckets" ]; then
    echo "  (no TF-tagged buckets found)"
    return
  fi
  while IFS= read -r bucket; do
    [ -z "$bucket" ] && continue
    echo "  Emptying ${bucket}..."
    aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
    python3 scripts/empty-versioned-bucket.py "${bucket}" 2>/dev/null || true
  done <<< "$buckets"
}

# `terraform destroy` with automatic retry when BucketNotEmpty blocks deletion.
# Between attempts, we re-empty every TF-tagged bucket (tag-based discovery)
# so any new logs written by ALB/CloudFront/Firehose during the previous
# attempt get cleared before the next try.
tf_destroy_with_retry() {
  local dir="$1"
  shift
  local attempt
  for attempt in $(seq 1 "$TF_DESTROY_MAX_ATTEMPTS"); do
    echo "  [destroy attempt ${attempt}/${TF_DESTROY_MAX_ATTEMPTS}] ${dir}"
    if terraform -chdir="$dir" destroy -auto-approve -input=false "$@"; then
      return 0
    fi
    echo "  attempt ${attempt} failed; re-emptying tagged buckets and retrying..."
    empty_tagged_buckets
    sleep 5
  done
  echo "  destroy did not converge after ${TF_DESTROY_MAX_ATTEMPTS} attempts" >&2
  return 1
}

# Delete log groups whose names match any of the given patterns (in a region).
delete_log_groups_matching() {
  local region="$1"
  shift
  local groups
  groups="$(aws logs describe-log-groups --region "$region" --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)"
  for pattern in "$@"; do
    for lg in $groups; do
      case "$lg" in
        $pattern)
          aws logs delete-log-group --region "$region" --log-group-name "$lg" 2>/dev/null \
            && echo "  Deleted ${region}:${lg}" || true
          ;;
      esac
    done
  done
}

echo "=== Full Destroy: ${PROJECT_NAME}-${ENVIRONMENT} ==="

# --------------------------------------------------------------------------------
# 1. Disable alerts FIRST (before emptying buckets / tearing down)
# --------------------------------------------------------------------------------
echo ""
echo "--- [1/8] Disable alerts (S3 notifications + CloudWatch alarms) ---"
disable_alerts

# --------------------------------------------------------------------------------
# 2. Delete ECS Services
# --------------------------------------------------------------------------------
echo ""
echo "--- [2/8] Delete ECS Services ---"
for service in user-api admin-api; do
  echo "  Deleting ${service}..."
  (cd "ecs/${service}" && ecspresso delete --force --terminate 2>&1 | tail -1) || true
done

echo "  Waiting for services to drain..."
for service in user-api admin-api; do
  TIMEOUT=60
  while [ "$(aws ecs describe-services --cluster ${PROJECT_NAME}-${ENVIRONMENT} --services ${service} --query 'services[0].status' --output text 2>/dev/null)" = "DRAINING" ] && [ $TIMEOUT -gt 0 ]; do
    sleep 5
    TIMEOUT=$((TIMEOUT - 1))
  done
done
echo "  done"

# --------------------------------------------------------------------------------
# 3. Empty S3 Buckets (first pass - before terraform destroy)
# --------------------------------------------------------------------------------
echo ""
echo "--- [3/8] Empty S3 Buckets (first pass, tag-based discovery) ---"
empty_tagged_buckets

# --------------------------------------------------------------------------------
# 4. Delete ECR Pull-through Cache Repos (AWS auto-creates these, not TF-tagged)
# --------------------------------------------------------------------------------
echo ""
echo "--- [4/8] Delete ECR Cache Repos ---"
repos=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `ecr-public/`)].repositoryName' --output text 2>/dev/null || true)
for repo in $repos; do
  echo "  Deleting ${repo}"
  aws ecr delete-repository --repository-name "${repo}" --force 2>/dev/null || true
done

# --------------------------------------------------------------------------------
# 5. Destroy Project Infrastructure (retry + re-empty on BucketNotEmpty)
# --------------------------------------------------------------------------------
echo ""
echo "--- [5/8] Destroy Project Infrastructure ---"
terraform -chdir=terraform/project/environments/${ENVIRONMENT} init -upgrade -input=false
tf_destroy_with_retry "terraform/project/environments/${ENVIRONMENT}"

# --------------------------------------------------------------------------------
# 6. Empty S3 Buckets (second pass - belt-and-suspenders before shared destroy)
# --------------------------------------------------------------------------------
echo ""
echo "--- [6/8] Empty S3 Buckets (second pass, tag-based discovery) ---"
empty_tagged_buckets

# --------------------------------------------------------------------------------
# 7. Destroy Shared Infrastructure (retry + re-empty; -refresh=false for PHZ)
# --------------------------------------------------------------------------------
echo ""
echo "--- [7/8] Destroy Shared Infrastructure ---"
terraform -chdir=terraform/shared/environments/${ENVIRONMENT} init -upgrade -input=false
# -refresh=false avoids dns_entry[0] empty collection error during endpoint+PHZ destroy
tf_destroy_with_retry "terraform/shared/environments/${ENVIRONMENT}" -refresh=false

# --------------------------------------------------------------------------------
# 8. Cleanup orphaned CloudWatch Log Groups (AWS auto-creates these; not TF-managed)
# --------------------------------------------------------------------------------
echo ""
echo "--- [8/8] Cleanup orphan Log Groups (pattern-based) ---"
# Patterns cover: VPC flow logs, ECS task/exec logs for our cluster, and WAF logs.
delete_log_groups_matching "$AWS_REGION" \
  "/aws/vpc/flow-log/*" \
  "/ecs/${PROJECT_NAME}-${ENVIRONMENT}/*"
delete_log_groups_matching "us-east-1" \
  "aws-waf-logs-${PROJECT_NAME}-${ENVIRONMENT}-*"

echo ""
echo "=== Destroy Complete ==="
