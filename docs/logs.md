# ログ一覧

## CloudWatch Logs

- **ECS アプリケーションログ** — `/ecs/{project}-{env}/{service}` (user-api, admin-api)
  - 保持: 30日, KMS暗号化あり
  - FireLens (Fluent Bit) 経由で app/nginx コンテナログを出力
  - `type=audit` のログは Firehose へルーティング（CloudWatch からは除外）
  - `terraform/project/modules/app/logging.tf:5-15`

- **FireLens ログルーター自身のログ** — `/ecs/{project}-{env}/{service}` (同上グループ、prefix: `firelens/`)
  - awslogs ドライバで直接出力（FireLens 自身は awsfirelens を使えないため）
  - `ecs/*/ecs-task-def.jsonnet` log_router コンテナ

- **VPC フローログ (project)** — `/aws/vpc/flow-log/{project}-{env}`
  - 保持: 30日, KMS暗号化あり, traffic_type: ALL
  - `terraform/project/modules/network/vpc_flow_logs.tf`

- **VPC フローログ (shared)** — `/aws/vpc/flow-log/{project}-{env}-shared`
  - 保持: 30日, KMS暗号化あり, traffic_type: ALL
  - `terraform/shared/modules/network/vpc_flow_logs.tf`

- **WAF ログ** — `aws-waf-logs-{project}-{env}-{lane}` (us-east-1)
  - 保持: 30日, KMS暗号化なし（us-east-1 に KMS キー未作成）
  - `terraform/project/modules/cdn/waf.tf`

## S3

- **ALB アクセスログ** — `{project}-{env}-access-logs-{account_id}` prefix: `alb/{lane}/`
  - ライフサイクル: 90日→GLACIER, 365日→削除
  - 暗号化: AES256（AWS仕様で SSE-S3 必須）
  - `terraform/project/modules/lb/alb.tf`

- **CloudFront 標準ログ** — `{project}-{env}-access-logs-{account_id}` prefix: `cloudfront/{lane}/`
  - ライフサイクル: 同上
  - 暗号化: AES256（AWS仕様で SSE-S3 必須）
  - `terraform/project/modules/cdn/cloudfront.tf`

- **S3 アクセスログ (assets)** — `{project}-{env}-access-logs-{account_id}` prefix: `s3/{lane}/`
  - `terraform/project/modules/storage/s3.tf`

- **S3 アクセスログ (artifact)** — `{project}-{env}-access-logs-{account_id}` prefix: `artifact/`
  - `terraform/project/modules/cicd/s3.tf`

- **S3 アクセスログ (audit-logs)** — `{project}-{env}-access-logs-{account_id}` prefix: `audit-logs/`
  - `terraform/project/modules/app/audit_logs.tf`

- **監査ログ** — `{project}-{env}-audit-logs-{account_id}` prefix: `audit/year=YYYY/month=MM/day=DD/`
  - Firehose 経由で S3 に保存、GZIP 圧縮
  - ライフサイクル: 90日→GLACIER, 365日→削除
  - 暗号化: KMS (aws:kms)
  - `terraform/project/modules/app/audit_logs.tf`

## Kinesis Data Firehose

- **監査ログストリーム** — `{project}-{env}-audit-logs`
  - バッファ: 5MB / 60秒
  - 圧縮: GZIP
  - エラー出力: `audit-errors/year=YYYY/month=MM/day=DD/{error-type}/`
  - `terraform/project/modules/app/audit_logs.tf`

## shared VPC 側 (S3)

- **ALB アクセスログ (shared)** — `{project}-{env}-access-logs` (account_id なし)
  - 暗号化: AES256
  - `terraform/modules/logging/s3.tf`
