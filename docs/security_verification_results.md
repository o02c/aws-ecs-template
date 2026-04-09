# セキュリティ禁止事項 検証結果

> 検証日: 2026-04-03 (全量再検証) → 2026-04-06 更新
> 対象: docs/security_gide_template.md 第2章の禁止事項 全量
> 備考: ビルド(CodeBuild)関連の制約は別件で対応。TGW/IGW/NAT GWはVPCエンドポイント構成により不要と判断。

---

## 違反一覧（7件）

### 1. シークレットの平文管理

**禁止事項:** 2.2.33 [手動] Secrets Managerを用いずにパスワード等のシークレットを管理することの禁止

| 箇所 | 内容 |
|------|------|
| `terraform/project/environments/dev/secret.auto.tfvars:2` | DBマスターパスワードが平文 |
| `ecs/admin-api/ecs-task-def.jsonnet:89-90` | DJANGO_SECRET_KEY が平文環境変数 |
| `ecs/user-api/ecs-task-def.jsonnet:91-92` | 同上 |

---

### 2. VPCエンドポイントのDenyポリシー未設定

**禁止事項:** 2.2.19 #14 [手動] VPCエンドポイントポリシーに他AWSアカウントプリンシパル拒否Denyポリシー必須

| 箇所 | 内容 |
|------|------|
| `terraform/shared/modules/network/vpc_endpoints.tf:5` | gateway endpoint: policy なし |
| `terraform/project/modules/network/vpc_endpoints.tf:5` | interface endpoint: policy なし |
| `terraform/project/modules/network/vpc_endpoints.tf:24` | gateway endpoint: policy なし |

---

### 3. VPCフローログ未設定

**禁止事項:** 2.2.19 #2 [SCP] VPCフローログを無効にすることの禁止

| 箇所 | 内容 |
|------|------|
| `terraform/shared/modules/network/vpc.tf` | shared VPC にフローログなし |
| `terraform/project/modules/network/vpc.tf` | project VPC にフローログなし |

---

### 4. S3バケットのKMS暗号化未設定

**禁止事項:** 2.2.16 A-#3 [SCP] KMSキーで暗号化されていないS3バケットの作成禁止

| バケット | 箇所 | 現状 |
|---------|------|------|
| access-logs (project) | `terraform/project/modules/logging/s3.tf:21-29` | AES256のみ |
| access-logs (shared) | `terraform/modules/logging/s3.tf:21-29` | AES256のみ |
| artifact | `terraform/project/modules/cicd/s3.tf:21-29` | AES256のみ |

---

### 5. S3バケットのサーバーアクセスログ未設定

**禁止事項:** 2.2.16 C-#7 [SCP] サーバーアクセスログが無効なS3バケットの作成禁止

| バケット | 箇所 | 現状 |
|---------|------|------|
| artifact | `terraform/project/modules/cicd/s3.tf` | logging 未設定 |
| audit-logs | `terraform/project/modules/app/audit_logs.tf` | logging 未設定 |

---

### 6. S3 access-logsバケットのSSL強制未設定

**禁止事項:** 2.2.16 C-#6 [SCP] SSLを要求しないバケットポリシーの禁止

| バケット | 箇所 | 現状 |
|---------|------|------|
| access-logs (project) | `terraform/project/modules/logging/bucket_policy.tf` | DenyInsecureTransport なし |
| access-logs (shared) | `terraform/modules/logging/s3.tf` | DenyInsecureTransport なし |

---

### 7. WAF Web ACLのログ記録未設定

**禁止事項:** 2.2.35 #2 [SCP] / #3 [手動] Web ACLのログ記録無効化禁止

| 箇所 | 現状 |
|------|------|
| `terraform/project/modules/cdn/waf.tf` | `aws_wafv2_web_acl_logging_configuration` が存在しない |

---

## TGW/IGW/NAT GW について

VPCエンドポイントで全AWSサービスアクセスが完結するため、以下は**不要と判断**:
- Transit Gateway (`shared/modules/network/transit_gateway.tf`)
- Internet Gateway (`shared/modules/network/vpc.tf`, `project/modules/network/vpc.tf`)
- IGW へのルート (`shared/modules/network/route_tables.tf`)
- shared VPC 自体（egress 共有が目的のため）

これらを削除すれば、SCP個別許可も不要になる。
インターネット接続無OUで運用可能。

---

## 禁止事項違反ではないもの

| 指摘 | 除外理由 |
|------|----------|
| KMS kms:* ポリシー | サービススコープ。Action=`"*"` かつ Resource=`"*"` ではない |
| ECR 暗号化未設定 | 禁止事項 2.2.8 はVPCエンドポイント経由のみ。暗号化の記載なし |
| Aurora publicly_accessible 未明示 | デフォルト false で実質準拠 |
| DNS Firewall マネージドリスト未使用 | 第3章の推奨事項。第2章の禁止事項ではない |
| 共通 #2 us-east-1 リソース | CloudFront用WAF/ACMは仕様上必須 |
| access-logs の外部エンティティ許可 | ELBアカウントからのログ書き込みはAWS仕様上必須 |
