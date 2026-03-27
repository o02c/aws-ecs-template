set dotenv-load

tf_dir := "terraform/environments/dev"

# --------------------------------------------------------------------------------
# Terraform
# --------------------------------------------------------------------------------

tf-init:
    terraform -chdir={{tf_dir}} init

tf-plan:
    terraform -chdir={{tf_dir}} plan

tf-apply:
    terraform -chdir={{tf_dir}} apply

tf-destroy:
    terraform -chdir={{tf_dir}} destroy

# --------------------------------------------------------------------------------
# Key Management
# --------------------------------------------------------------------------------

generate-signing-keypair:
    bash scripts/generate-signing-keypair.sh

# --------------------------------------------------------------------------------
# Docker
# --------------------------------------------------------------------------------

docker-build service:
    docker build -t {{service}}:latest apps/{{service}}

docker-push service:
    #!/usr/bin/env bash
    set -euo pipefail
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=${AWS_REGION:-ap-northeast-1}
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
    REPO="${PROJECT_NAME:-myapp}-${ENVIRONMENT:-dev}-{{service}}"
    aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URI}"
    docker tag {{service}}:latest "${ECR_URI}/${REPO}:latest"
    docker push "${ECR_URI}/${REPO}:latest"

# --------------------------------------------------------------------------------
# Deploy
# --------------------------------------------------------------------------------

deploy service:
    ecspresso deploy --config ecs/{{service}}/ecspresso.yml
