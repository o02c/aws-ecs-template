#!/usr/bin/env bash
# Comprehensive post-deploy verification: HTTPS reachability, TLS version,
# and log delivery across every destination the stack writes to.
# Usage: bash scripts/verify-deploy.sh
set -uo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="ap-northeast-1"

PROJECT_NAME="myapp"
ENVIRONMENT="dev"
DOMAIN_NAME="${DOMAIN_NAME:-o2c.click}"
LANES=(user admin)
# SERVICES intentionally not listed — ECS logs skip CloudWatch and go through
# Firehose → S3 ${ACCESS_LOG_BUCKET}/ecs-logs/ and ${ACCESS_LOG_BUCKET}/audit/.

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ACCESS_LOG_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-access-logs-${ACCOUNT_ID}"

FAILED=0
ok()   { echo "  OK    $*"; }
warn() { echo "  WARN  $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }

echo "=== Verify Deploy: ${PROJECT_NAME}-${ENVIRONMENT} @ ${DOMAIN_NAME} ==="

# --------------------------------------------------------------------------------
# 1. HTTPS health check (all lanes)
# --------------------------------------------------------------------------------
echo ""
echo "--- [1/6] HTTPS Health ---"
for lane in "${LANES[@]}"; do
  url="https://${lane}.${DOMAIN_NAME}/health"
  code=$(curl -sSk --max-time 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    ok "${url} → 200"
  else
    fail "${url} → ${code}"
  fi
done

# --------------------------------------------------------------------------------
# 2. TLS / cert hygiene
# --------------------------------------------------------------------------------
echo ""
echo "--- [2/6] TLS / Certificate ---"
for lane in "${LANES[@]}"; do
  host="${lane}.${DOMAIN_NAME}"
  tls_info=$(echo | openssl s_client -connect "${host}:443" -servername "${host}" -brief 2>&1 | grep -E 'Protocol version|Ciphersuite|Verification' || true)
  protocol=$(echo "$tls_info" | grep 'Protocol version' | awk -F': ' '{print $2}')
  verification=$(echo "$tls_info" | grep '^Verification' | awk -F': ' '{print $2}')
  if [[ "$protocol" == "TLSv1.3" || "$protocol" == "TLSv1.2" ]] && [[ "$verification" == "OK" ]]; then
    ok "${host} ${protocol} cert:${verification}"
  else
    fail "${host} protocol=${protocol:-n/a} cert=${verification:-n/a}"
  fi
done

for lane in "${LANES[@]}"; do
  host="${lane}.${DOMAIN_NAME}"
  if echo | openssl s_client -connect "${host}:443" -servername "${host}" -tls1_1 2>&1 | grep -q 'Cipher is'; then
    fail "${host} accepted TLS 1.1"
  else
    ok "${host} refused TLS 1.1"
  fi
done

# --------------------------------------------------------------------------------
# 3. Generate traffic to populate log destinations
# --------------------------------------------------------------------------------
echo ""
echo "--- [3/6] Generate traffic (3 requests per lane) ---"
for lane in "${LANES[@]}"; do
  for _ in 1 2 3; do
    curl -sSk --max-time 10 "https://${lane}.${DOMAIN_NAME}/health" > /dev/null 2>&1 || true
  done
done
echo "  Waiting 120s for downstream log pipelines (Firehose 60s buffer, VPC flow ~1min)..."
sleep 120

# --------------------------------------------------------------------------------
# 4. CloudWatch Logs destinations (infra-level only — ECS logs go to S3)
# --------------------------------------------------------------------------------
echo ""
echo "--- [4/6] CloudWatch Logs (VPC flow + WAF only) ---"

check_cw_group_has_events() {
  local region="$1" lg="$2" label="$3"
  if ! aws logs describe-log-groups --region "$region" --log-group-name-prefix "$lg" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "^${lg}$"; then
    fail "${label}: log group ${lg} missing"
    return
  fi
  local events
  events=$(aws logs filter-log-events --region "$region" --log-group-name "$lg" \
            --start-time "$(($(date +%s) * 1000 - 300000))" --limit 1 \
            --query 'events | length(@)' --output text 2>/dev/null || echo "0")
  if [ "${events:-0}" -gt 0 ]; then
    ok "${label}: ${lg} (recent events)"
  else
    warn "${label}: ${lg} exists but no events in last 5min"
  fi
}

# VPC flow logs (shared + project)
check_cw_group_has_events "$AWS_REGION" "/aws/vpc/flow-log/shared-${ENVIRONMENT}"          "VPC flow shared"
check_cw_group_has_events "$AWS_REGION" "/aws/vpc/flow-log/${PROJECT_NAME}-${ENVIRONMENT}" "VPC flow project"
# WAF logs (us-east-1)
for lane in "${LANES[@]}"; do
  check_cw_group_has_events "us-east-1" "aws-waf-logs-${PROJECT_NAME}-${ENVIRONMENT}-${lane}" "WAF ${lane}"
done

# --------------------------------------------------------------------------------
# 5. S3 Log Destinations (all logs land in the single access-log bucket)
# --------------------------------------------------------------------------------
echo ""
echo "--- [5/6] S3 Log Destinations (single bucket, prefix-separated) ---"

check_s3_prefix() {
  local bucket="$1" prefix="$2" label="$3" mandatory="${4:-1}"
  local count
  count=$(aws s3 ls "s3://${bucket}/${prefix}" --recursive 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
  if [ "${count:-0}" -gt 0 ]; then
    ok "${label}: s3://${bucket}/${prefix} (${count} objects)"
  elif [ "$mandatory" = "1" ]; then
    warn "${label}: s3://${bucket}/${prefix} empty (CloudFront up to 30min; may need more time)"
  else
    ok "${label}: s3://${bucket}/${prefix} empty (optional)"
  fi
}

# ALB access logs
for lane in "${LANES[@]}"; do
  check_s3_prefix "$ACCESS_LOG_BUCKET" "alb/${lane}/" "ALB ${lane}"
done
# CloudFront access logs
for lane in "${LANES[@]}"; do
  check_s3_prefix "$ACCESS_LOG_BUCKET" "cloudfront/${lane}/" "CloudFront ${lane}"
done
# S3 bucket access logs (asset buckets)
for lane in "${LANES[@]}"; do
  check_s3_prefix "$ACCESS_LOG_BUCKET" "s3/${lane}/" "S3 asset-access ${lane}" 0
done
# ECS container logs (via Firehose, all non-audit records)
check_s3_prefix "$ACCESS_LOG_BUCKET" "ecs-logs/" "ECS logs (Firehose)" 0
# Audit records (type=audit, Firehose separated)
check_s3_prefix "$ACCESS_LOG_BUCKET" "audit/" "Audit (Firehose)" 0
# Fluent Bit config object (uploaded during apply)
check_s3_prefix "$ACCESS_LOG_BUCKET" "fluent-bit/" "FireLens config" 0

# --------------------------------------------------------------------------------
# 6. Bucket / log group security posture (spot checks)
# --------------------------------------------------------------------------------
echo ""
echo "--- [6/6] Security Posture Spot Checks ---"

for b in "$ACCESS_LOG_BUCKET" "${PROJECT_NAME}-${ENVIRONMENT}-user-assets" "${PROJECT_NAME}-${ENVIRONMENT}-admin-assets"; do
  pab=$(aws s3api get-public-access-block --bucket "$b" --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null || echo "{}")
  if echo "$pab" | grep -q '"BlockPublicAcls": true' && echo "$pab" | grep -q '"RestrictPublicBuckets": true'; then
    ok "PublicAccessBlock enforced: ${b}"
  else
    fail "PublicAccessBlock NOT enforced: ${b}"
  fi
done

for b in "$ACCESS_LOG_BUCKET" "${PROJECT_NAME}-${ENVIRONMENT}-user-assets"; do
  policy=$(aws s3api get-bucket-policy --bucket "$b" --query Policy --output text 2>/dev/null || echo "")
  if echo "$policy" | grep -q 'SecureTransport'; then
    ok "SSL-only policy present: ${b}"
  else
    warn "SSL-only policy MISSING: ${b}"
  fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "=== Verify PASSED ==="
  exit 0
else
  echo "=== Verify FAILED ==="
  exit 1
fi
