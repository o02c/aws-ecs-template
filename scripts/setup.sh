#!/usr/bin/env bash
set -euo pipefail

# Initial setup: terraform init/apply + deploy all apps
# Usage: ./scripts/setup.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform/environments/dev"
AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Initial Setup ==="
echo "Account: $AWS_ACCOUNT_ID"
echo "Region:  $AWS_REGION"
echo ""

# --------------------------------------------------------------------------------
# Step 1: Terraform
# --------------------------------------------------------------------------------
echo "--- Terraform Init ---"
cd "$TF_DIR"
terraform init -upgrade

echo ""
echo "--- Terraform Plan ---"
terraform plan

echo ""
read -p "Apply? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "--- Terraform Apply ---"
terraform apply -auto-approve

# --------------------------------------------------------------------------------
# Step 2: Deploy apps
# --------------------------------------------------------------------------------
echo ""
echo "--- Deploying apps ---"
"$SCRIPT_DIR/deploy.sh"

echo ""
echo "=== Setup Complete ==="
