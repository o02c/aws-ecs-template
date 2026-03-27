#!/usr/bin/env bash
set -euo pipefail

# Destroy everything in one command
# Usage: ./scripts/destroy.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform/environments/dev"

SERVICES=("user-api" "admin-api")
LANES=("user" "admin")
PROJECT_NAME="myapp"
ENVIRONMENT="dev"

echo "=== DESTROY ALL RESOURCES ==="
echo ""
echo "This will delete:"
echo "  - ECS services (user-api, admin-api)"
echo "  - S3 bucket contents"
echo "  - All Terraform-managed infrastructure"
echo ""
read -p "Are you sure? (type 'destroy' to confirm): " confirm
if [[ "$confirm" != "destroy" ]]; then
  echo "Aborted."
  exit 1
fi

# --------------------------------------------------------------------------------
# Step 1: Delete ECS services
# --------------------------------------------------------------------------------
echo ""
echo "--- Deleting ECS services ---"
for service in "${SERVICES[@]}"; do
  echo "Deleting $service..."
  cd "$PROJECT_ROOT/ecs/$service"
  ecspresso delete --config ecspresso.yml --force --terminate || true
done

# --------------------------------------------------------------------------------
# Step 2: Empty S3 buckets (including versioned objects)
# --------------------------------------------------------------------------------
echo ""
echo "--- Emptying S3 buckets ---"
for lane in "${LANES[@]}"; do
  bucket="$PROJECT_NAME-$ENVIRONMENT-$lane-assets"
  echo "Emptying $bucket..."

  # Delete all object versions
  aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
objects = []
for v in data.get('Versions', []):
    objects.append({'Key': v['Key'], 'VersionId': v['VersionId']})
for m in data.get('DeleteMarkers', []):
    objects.append({'Key': m['Key'], 'VersionId': m['VersionId']})
if objects:
    print(json.dumps({'Objects': objects, 'Quiet': True}))
else:
    sys.exit(1)
" > /tmp/del-objects.json 2>/dev/null && \
    aws s3api delete-objects --bucket "$bucket" --delete "file:///tmp/del-objects.json" > /dev/null 2>&1 || true

  echo "  done"
done

# --------------------------------------------------------------------------------
# Step 3: Terraform destroy
# --------------------------------------------------------------------------------
echo ""
echo "--- Terraform Destroy ---"
cd "$TF_DIR"
terraform destroy -auto-approve

echo ""
echo "=== Destroy Complete ==="
