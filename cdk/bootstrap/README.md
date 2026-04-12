# CDK Bootstrap - CodeBuild Deployer

クライアント環境で `cdk deploy` が使えない場合の鶏卵問題を解決するための CloudFormation テンプレート。

CodeBuild が `cdk synth` でテンプレートを生成し、`aws cloudformation deploy --role-arn` で各スタックをデプロイする。

## 前提条件

- Shared VPC がデプロイ済み (VPC, Private Subnet, Security Group)
- CloudFormation サービスロールが作成済み
- 以下の VPC Endpoint が利用可能:
  - `s3` (Gateway)
  - `cloudformation` (Interface)
  - `logs` (Interface)
  - `codebuild` (Interface)
  - `sts` (Interface)

## セットアップ手順

### 1. パラメータの確認

| パラメータ | 説明 | 例 |
|-----------|------|-----|
| CfnServiceRoleArn | CFn サービスロール ARN | `arn:aws:iam::123456789012:role/cfn-service-role` |
| VpcId | CodeBuild 配置先 VPC | `vpc-0123456789abcdef0` |
| SubnetIds | Private Subnet IDs | `subnet-aaa,subnet-bbb` |
| SecurityGroupId | CodeBuild 用 SG | `sg-0123456789abcdef0` |
| ProjectName | プロジェクト名 | `myapp` |
| Environment | 環境名 | `dev` |

### 2. CloudFormation テンプレートのデプロイ

CloudFormation コンソールから `codebuild-deployer.yaml` をアップロード:

1. CloudFormation コンソール > スタックの作成 > 新しいリソースを使用
2. テンプレートファイルのアップロードで `codebuild-deployer.yaml` を選択
3. パラメータを入力
4. **IAM ロール**: CFn サービスロールを指定 (2.2.20 #2 準拠)
5. スタック作成

### 3. ソースコード zip の作成とアップロード

`node_modules` を含めた zip を作成し、S3 にアップロードする。

```bash
# shared 用
cd cdk/shared
npm ci
cd ../..
zip -r myapp-shared-source.zip cdk/shared/ cdk/bootstrap/buildspec-shared.yml
aws s3 cp myapp-shared-source.zip s3://myapp-dev-codebuild-source/myapp-shared-source.zip

# project 用
cd cdk/project
npm ci
cd ../..
zip -r myapp-project-source.zip cdk/project/ cdk/bootstrap/buildspec-project.yml
aws s3 cp myapp-project-source.zip s3://myapp-dev-codebuild-source/myapp-project-source.zip
```

### 4. CodeBuild の実行

以下のいずれかの方法でデプロイを実行:

**手動実行:**

```bash
# shared
aws codebuild start-build --project-name myapp-dev-shared-deployer

# project
aws codebuild start-build --project-name myapp-dev-project-deployer
```

**S3 プッシュトリガー (自動):**

S3 バケットへの zip アップロードで EventBridge 経由で自動的に CodeBuild が起動する。
EventBridge S3 通知を有効にするには、S3 バケットで EventBridge 通知を ON にする必要がある。

```bash
aws s3api put-bucket-notification-configuration \
  --bucket myapp-dev-codebuild-source \
  --notification-configuration '{"EventBridgeConfiguration": {}}'
```

## デプロイ順序

1. **shared-deployer** を先に実行 (VPC, TGW, IAM 等)
2. shared 完了後に **project-deployer** を実行

project-deployer は依存順序を考慮して以下の順でスタックをデプロイする:

1. `Foundation` (VPC, KMS, Logging)
2. `Database` (Aurora)
3. `Lane-user` (ALB, S3, CloudFront)
4. `Lane-admin` (ALB, S3, CloudFront)
5. `Application` (ECS, ECR, IAM)

## ファイル構成

```
cdk/bootstrap/
  codebuild-deployer.yaml    # CloudFormation テンプレート (本ファイル)
  buildspec-shared.yml       # shared 用 buildspec
  buildspec-project.yml      # project 用 buildspec
  README.md                  # セットアップ手順 (本ファイル)
```
