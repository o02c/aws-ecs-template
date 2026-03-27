#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------------
# Generate RSA keypair for CloudFront Signed URLs
#   - Private key → Secrets Manager
#   - Public key PEM → stdout (for Terraform variable)
# --------------------------------------------------------------------------------

SECRET_NAME="${SECRET_NAME:-cloudfront-signing-key}"
KEY_BITS=2048
TMPDIR_PATH=$(mktemp -d)
trap 'rm -rf "${TMPDIR_PATH}"' EXIT

PRIVATE_KEY="${TMPDIR_PATH}/private.pem"
PUBLIC_KEY="${TMPDIR_PATH}/public.pem"

echo "Generating RSA ${KEY_BITS}-bit keypair..."
openssl genrsa -out "${PRIVATE_KEY}" "${KEY_BITS}" 2>/dev/null
openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}" 2>/dev/null

echo "Storing private key in Secrets Manager (${SECRET_NAME})..."
if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "file://${PRIVATE_KEY}"
  echo "Updated existing secret."
else
  aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --description "CloudFront signing private key" \
    --secret-string "file://${PRIVATE_KEY}"
  echo "Created new secret."
fi

SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" --query ARN --output text)

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Secret ARN (for Terraform variable cloudfront_signing_key_secret_arn):"
echo "  ${SECRET_ARN}"
echo ""
echo "Public key PEM (for Terraform variable cloudfront_signing_public_key_pem):"
echo "---"
cat "${PUBLIC_KEY}"
echo "---"
echo ""
echo "Add to secret.auto.tfvars:"
echo '  cloudfront_signing_key_secret_arn = "'"${SECRET_ARN}"'"'
echo '  cloudfront_signing_public_key_pem = <<-EOF'
cat "${PUBLIC_KEY}"
echo 'EOF'
