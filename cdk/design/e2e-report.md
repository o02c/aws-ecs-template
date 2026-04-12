# E2E Synth Verification Report

## 1. Stack 一覧とリソース数

### shared (`cdk synth -c env=dev`)

| Stack | Stack Name | Resources |
|-------|-----------|-----------|
| NetworkStack | Shared-dev-Network | 68 |
| IamStack | Shared-dev-Iam | 2 |
| **Total** | | **70** |

### project (`cdk synth -c env=dev`)

| Stack | Stack Name | Resources |
|-------|-----------|-----------|
| FoundationStack | myapp-dev-Foundation | 49 |
| DatabaseStack | myapp-dev-Database | 12 |
| Lane-user | myapp-dev-Lane-user | 18 |
| Lane-admin | myapp-dev-Lane-admin | 18 |
| ApplicationStack | myapp-dev-Application | 27 |
| **Total** | | **124** |

## 2. template-only モード検証

`cdk synth -c env=client-prod` で `BootstraplessSynthesizer` を使用した synth が成功。

| Stack | Stack Name | Resources |
|-------|-----------|-----------|
| FoundationStack | myapp-prod-Foundation | 49 |
| DatabaseStack | myapp-prod-Database | 12 |
| Lane-user | myapp-prod-Lane-user | 18 |
| Lane-admin | myapp-prod-Lane-admin | 18 |
| ApplicationStack | myapp-prod-Application | 27 |
| **Total** | | **124** |

- `deployMode: 'template-only'` の config で `BootstraplessSynthesizer` が自動適用される
- `cdk bootstrap` 不要でテンプレート生成可能
- 各 Stack に個別の `BootstraplessSynthesizer` インスタンスが割り当てられる

## 3. テスト結果

### shared

- Test Suites: 4 passed (4 total)
- Tests: 35 passed (35 total)
- テスト対象: network-stack, iam-stack, tagging aspect, encryption aspect

### project

- Test Suites: 6 passed (6 total)
- Tests: 85 passed (85 total)
- テスト対象: foundation-stack, database-stack, lane-stack, application-stack, tagging aspect, encryption aspect

**Total: 10 suites, 120 tests, all passed**

## 4. 既知の制約事項

### WAF us-east-1

- CloudFront 用 WAF WebACL は us-east-1 に作成が必要
- クライアント環境 (template-only) では日本リージョン以外のリソース作成が禁止されているため、WAF は別途手動 or 管理アカウント提供のテンプレートで対応

### crossRegionReferences

- CDK の `crossRegionReferences: true` はクライアント環境で使用不可
  - us-east-1 に Lambda Custom Resource, CFn 補助 Stack, SSM Parameter, bootstrap stack を自動生成するため
- 開発環境 (`deployMode: cdk-deploy`) では使用可能
- CloudFront 用 ACM 証明書 (us-east-1) は外部で事前作成し、SSM 経由で参照

### Inspector 有効化

- `AWS::InspectorV2::Filter` を使用しているが、Inspector V2 がアカウントレベルで有効化されている前提
- 未有効化の場合、ApplicationStack のデプロイでエラーとなる
- 事前に AWS コンソール or CLI で `aws inspector2 enable --resource-types ECR` を実行

## 5. Deploy 手順

### 前提条件

1. AWS CLI の認証情報が設定済み
2. `cdk bootstrap` 実行済み (dev 環境のみ、template-only 不要)
3. 秘匿値 (SSM SecureString) が事前作成済み

### デプロイ順序

```bash
# 1. shared infrastructure (VPC, TGW, Endpoints, IAM)
cd cdk/shared && npx cdk deploy -c env=dev --all --require-approval broadening

# 2. project infrastructure (VPC, DB, Lanes, ECS)
cd cdk/project && npx cdk deploy -c env=dev --all --require-approval broadening

# or one-liner:
just cdk-deploy-all env=dev
```

### 削除順序 (デプロイの逆順)

```bash
# 1. project infrastructure first
cd cdk/project && npx cdk destroy -c env=dev --all --force

# 2. then shared infrastructure
cd cdk/shared && npx cdk destroy -c env=dev --all --force

# or one-liner:
just cdk-destroy-all env=dev
```

### template-only モード (クライアント環境)

```bash
# テンプレート生成のみ (デプロイしない)
cd cdk/project && npx cdk synth -c env=client-prod

# 生成されたテンプレートは cdk.out/assembly-myapp-prod/ に格納
# CFn コンソール or CLI で手動デプロイ
```
