#!/usr/bin/env bash
# Enable S3 Object Lock on the per-lane front-end assets buckets.
#
# object_lock_enabled can only be set at bucket creation, so Terraform must
# REPLACE each assets bucket. This script makes that non-destructive to the
# served content by evacuating → recreating → restoring:
#
#   1. backup   : sync each bucket's current objects to a local dir
#   2. empty    : remove all versions + delete markers (so TF can drop the bucket)
#   3. apply    : terraform apply recreates the bucket WITH Object Lock
#   4. restore  : re-upload assets; index.html is re-placed with `no-cache`,
#                 everything else with a long immutable cache
#   5. verify   : Object Lock config / retention + index.html Cache-Control + HTTPS
#
# Usage:
#   bash scripts/migrate-assets-object-lock.sh            # interactive confirm
#   YES=1 bash scripts/migrate-assets-object-lock.sh      # skip confirm
#
# Env overrides: PROJECT_NAME, ENVIRONMENT, LANES, DOMAIN_NAME, APPLY_CMD, BACKUP_DIR
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"

PROJECT_NAME="${PROJECT_NAME:-myapp}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LANES="${LANES:-user admin}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
APPLY_CMD="${APPLY_CMD:-just project-apply-auto}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/${PROJECT_NAME}-${ENVIRONMENT}-assets-backup}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LONG_CACHE="public, max-age=31536000, immutable"
NO_CACHE="no-cache"

echo "=== Assets Object Lock migration: ${PROJECT_NAME}-${ENVIRONMENT} ==="
echo "Lanes      : ${LANES}"
echo "Backup dir : ${BACKUP_DIR}"
echo "Apply cmd  : ${APPLY_CMD}"
echo ""
echo "WARNING: each assets bucket will be REPLACED (terraform apply). Objects are"
echo "backed up locally and restored afterwards, but this is a destructive op."

if [ "${YES:-}" != "1" ]; then
  read -r -p "Type 'migrate' to continue: " confirm
  [ "$confirm" = "migrate" ] || { echo "Aborted."; exit 1; }
fi

# Default-lane (path_prefix "") serves from the bucket root; other lanes live
# under "<lane>/" (matches scripts/deploy.sh deploy_frontend layout).
lane_prefix() {
  [ "$1" = "user" ] && echo "" || echo "$1/"
}

bucket_name() { echo "${PROJECT_NAME}-${ENVIRONMENT}-$1-assets"; }

# --------------------------------------------------------------------------------
# 1. Backup
# --------------------------------------------------------------------------------
echo ""
echo "--- [1/5] Backup current objects ---"
for lane in $LANES; do
  bucket="$(bucket_name "$lane")"
  prefix="$(lane_prefix "$lane")"
  dest="${BACKUP_DIR}/${lane}"
  mkdir -p "$dest"
  echo "  s3://${bucket}/${prefix} → ${dest}"
  # Scope to the lane prefix so backup/restore are symmetric (non-default lanes
  # live under "<lane>/"); otherwise restore would double-nest the prefix.
  aws s3 sync "s3://${bucket}/${prefix}" "${dest}/" --quiet
done

# --------------------------------------------------------------------------------
# 2. Empty (versions + delete markers)
# --------------------------------------------------------------------------------
echo ""
echo "--- [2/5] Empty buckets ---"
for lane in $LANES; do
  bucket="$(bucket_name "$lane")"
  echo "  Emptying s3://${bucket}"
  aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true
  python3 scripts/empty-versioned-bucket.py "$bucket"
done

# --------------------------------------------------------------------------------
# 3. Apply (recreate with Object Lock)
# --------------------------------------------------------------------------------
echo ""
echo "--- [3/5] terraform apply (recreate buckets with Object Lock) ---"
eval "$APPLY_CMD"

# --------------------------------------------------------------------------------
# 4. Restore (index.html no-cache, rest immutable)
# --------------------------------------------------------------------------------
echo ""
echo "--- [4/5] Restore objects ---"
for lane in $LANES; do
  bucket="$(bucket_name "$lane")"
  src="${BACKUP_DIR}/${lane}"
  prefix="$(lane_prefix "$lane")"
  if [ -z "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "  (no backed-up objects for ${lane}, skipping)"
    continue
  fi
  echo "  ${src} → s3://${bucket}/${prefix}"
  # Everything except index.html gets a long immutable cache.
  aws s3 sync "${src}/" "s3://${bucket}/${prefix}" \
    --cache-control "$LONG_CACHE" --exclude "*index.html" --quiet
  # index.html (root + any nested) is re-placed with no-cache.
  aws s3 sync "${src}/" "s3://${bucket}/${prefix}" \
    --cache-control "$NO_CACHE" --exclude "*" --include "*index.html" --quiet
done

# --------------------------------------------------------------------------------
# 5. Verify
# --------------------------------------------------------------------------------
echo ""
echo "--- [5/5] Verify ---"
fail=0
for lane in $LANES; do
  bucket="$(bucket_name "$lane")"
  prefix="$(lane_prefix "$lane")"

  # Object Lock enabled + default retention
  mode=$(aws s3api get-object-lock-configuration --bucket "$bucket" \
    --query 'ObjectLockConfiguration.Rule.DefaultRetention.Mode' --output text 2>/dev/null || echo "NONE")
  days=$(aws s3api get-object-lock-configuration --bucket "$bucket" \
    --query 'ObjectLockConfiguration.Rule.DefaultRetention.Days' --output text 2>/dev/null || echo "?")
  if [ "$mode" = "GOVERNANCE" ]; then
    echo "  [OK]   ${bucket}: Object Lock ${mode} ${days}d"
  else
    echo "  [FAIL] ${bucket}: Object Lock not configured (mode=${mode})"
    fail=1
  fi

  # index.html Cache-Control (only if present)
  if aws s3api head-object --bucket "$bucket" --key "${prefix}index.html" >/dev/null 2>&1; then
    cc=$(aws s3api head-object --bucket "$bucket" --key "${prefix}index.html" \
      --query 'CacheControl' --output text 2>/dev/null || echo "")
    retain=$(aws s3api get-object-retention --bucket "$bucket" --key "${prefix}index.html" \
      --query 'Retention.Mode' --output text 2>/dev/null || echo "NONE")
    if [ "$cc" = "$NO_CACHE" ]; then
      echo "  [OK]   ${bucket}: ${prefix}index.html Cache-Control='${cc}', retention=${retain}"
    else
      echo "  [FAIL] ${bucket}: ${prefix}index.html Cache-Control='${cc}' (expected '${NO_CACHE}')"
      fail=1
    fi
  else
    echo "  [WARN] ${bucket}: ${prefix}index.html not found (nothing restored?)"
  fi
done

# HTTPS spot check via CloudFront (root serves the user-lane index.html)
if [ -n "$DOMAIN_NAME" ]; then
  echo ""
  echo "  HTTPS: https://${DOMAIN_NAME}/"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://${DOMAIN_NAME}/" || echo "000")
  if [ "$code" = "200" ]; then
    echo "  [OK]   GET / → ${code}"
  else
    echo "  [WARN] GET / → ${code} (CloudFront propagation / caching may need a moment)"
  fi
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "=== Migration completed WITH FAILURES (see [FAIL] above). Backup kept at ${BACKUP_DIR} ==="
  exit 1
fi
echo "=== Migration Complete === (backup retained at ${BACKUP_DIR})"
