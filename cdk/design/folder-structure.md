# CDK Folder Structure Design

## Context

Terraform が全社 NG になる可能性があるため、既存 Terraform 構成を AWS CDK (TypeScript) に移行する。
現行アーキテクチャ (CloudFront -> ALB -> ECS Fargate, Aurora, S3) を維持しつつ、
マルチアカウント・マルチ環境・マルチプロジェクト・レーン構成に対応する。

### 前提条件

| 項目 | 内容 |
|------|------|
| アカウント | 2 (本番 / 非本番) |
| 環境 | 最大 4 (dev, test, stg, prod) |
| 環境配置 | 非本番: dev, test, (stg) / 本番: prod |
| shared | 各アカウントに 1 つ (VPC, NAT GW, TGW, IAM, KMS) |
| プロジェクト | 環境ごとに 2+ (myapp, ...) |
| ECS デプロイ | ecspresso (CDK 管轄外) |
| チーム規模 | 1-3 名 (インフラ・アプリ兼任) |

### 設計原則

1. **リポジトリ分離**: shared と project は別リポジトリ。SSM Parameter Store のみで連携し、コード依存なし
2. **Config 駆動**: 新プロジェクト・環境追加はコード変更不要、config ファイル追加のみ
3. **Construct 化は再利用時のみ**: 2 箇所以上から使うものだけ Construct に切り出す。1 箇所のみなら Stack に直書き
4. **フラット優先**: ディレクトリ階層は最小限。同カテゴリ 3 ファイル以上でサブディレクトリ化
5. **秘匿値は CDK 外で管理**: CDK/CloudFormation で秘匿値を作成しない。事前作成 → 参照のみ
6. **SSM で疎結合**: リポジトリ間・Stack 間の参照は全て SSM Parameter Store

---

## 1. フォルダ構成

shared と project は最終的に別リポジトリとして運用する。
コードの共有は行わず、SSM Parameter Store の命名規則のみが契約 (IF) となる。

本テンプレートリポジトリでは `cdk/shared/` と `cdk/project/` に分けて格納する。
実運用時はそれぞれを独立リポジトリにコピーする。

```
cdk/
  shared/                          # → 実運用時は別リポ (aws-infra-shared)
    bin/
      app.ts                       # Entry point
    config/
      accounts.ts                  # Account ID / Region 定義
      environments/
        dev.ts                     # non-prod account 設定
        prod.ts                    # prod account 設定
    lib/
      constructs/                  # Construct (フラット配置)
        shared-vpc.ts              # Shared VPC + NAT GW + TGW + Endpoints
      stacks/
        network-stack.ts           # KMS + VPC + TGW + Endpoints
        iam-stack.ts               # IAM Users/Groups (直書き)
      stages/
        shared-stage.ts            # Stack 群をグループ化
      aspects/
        tagging.ts                 # default_tags 相当
        encryption.ts              # KMS 暗号化強制
      helpers/
        ssm.ts                     # SSM Parameter 書込ユーティリティ
        config-types.ts            # SharedConfig interface
    test/
      stacks/                      # Stack 単位のテスト
    cdk.json
    cdk.context.json
    package.json
    tsconfig.json
    jest.config.js

  project/                         # → 実運用時は別リポ (プロジェクトごとにコピー)
    bin/
      app.ts                       # Entry point
    config/
      accounts.ts                  # Account ID / Region 定義
      environments/
        dev.ts                     # myapp-dev 設定
        test.ts
        prod.ts
    lib/
      constructs/                  # Construct (フラット配置)
        project-vpc.ts             # Project VPC + TGW Attachment
        security-group-set.ts      # 空 SG シェルパターン
        aurora-serverless.ts       # Aurora PostgreSQL Serverless v2
        internal-alb.ts            # Internal ALB + Listener + TG
        asset-bucket.ts            # S3 + OAC + Versioning + Encryption
        lane-distribution.ts       # CloudFront + WAF + Route53 Alias
        application.ts             # ECS Cluster + ECR + IAM (統合)
        deploy-pipeline.ts         # CodePipeline + CodeBuild + EventBridge
        hosted-zone.ts             # Route53 + ACM (Regional + us-east-1)
      stacks/
        foundation-stack.ts        # KMS + Logging + VPC + DNS
        database-stack.ts          # Aurora (分離: 削除保護, 独立ライフサイクル)
        lane-stack.ts              # ALB + S3 + CloudFront (per-lane)
        application-stack.ts       # ECS Cluster + ECR + IAM
        cicd-stack.ts              # CodePipeline + CodeBuild (optional)
      stages/
        project-stage.ts           # Stack 群をグループ化
      aspects/
        tagging.ts                 # default_tags 相当
        encryption.ts              # KMS 暗号化強制
      helpers/
        ssm.ts                     # SSM Parameter 読み書きユーティリティ
        naming.ts                  # リソース命名規則 (<Project>-<Env>-<id>)
        config-types.ts            # ProjectConfig interface
    test/
      constructs/                  # Construct 単位のユニットテスト
      stacks/                      # Stack 単位のスナップショットテスト
    cdk.json
    cdk.context.json
    package.json
    tsconfig.json
    jest.config.js

  design/                          # 設計ドキュメント (本ファイル等)
```

### リポジトリ間の IF (SSM 命名規則)

shared と project のコード依存はゼロ。唯一の契約は SSM パラメータの命名規則:

```
/shared/<env>/infra/transit-gateway-id
/shared/<env>/infra/private-subnet-cidrs
/shared/<env>/infra/endpoint-phz-zone-ids
```

project 側は上記パスから SSM を読むだけ。shared のコードを参照・import しない。
この IF はドキュメント (本ファイル Section 5) で管理する。

### Construct 化の判断基準

**shared リポジトリ:**

| 分類 | 方針 | 理由 |
|------|------|------|
| SharedVpc | Construct に切り出す | 構成が大きく Stack から分離したい |
| IAM, KMS Keys | Stack に直書き | 各 1 箇所でしか使わない |

初期 Construct 数: **1 ファイル**

**project リポジトリ:**

| 分類 | 方針 | 理由 |
|------|------|------|
| ProjectVpc, InternalAlb, AssetBucket, LaneDistribution, AuroraServerless | Construct に切り出す | per-lane で複数回使用 or 構成が大きい |
| SecurityGroupSet, HostedZone | Construct に切り出す | Props IF が明確で再利用価値がある |
| Application (ECS+ECR+IAM) | 1 ファイルに統合 | 元は 3 ファイルだが常にセットで使う |
| KMS Keys, Logging | Stack に直書き | 各 1 箇所でしか使わない |

初期 Construct 数: **9 ファイル**

### コード共有について

shared と project で `tagging.ts`, `encryption.ts` 等が重複するが、意図的に許容する。
理由:
- npm パッケージ化の運用コスト > コード重複のコスト (1-3 名チーム)
- 各リポジトリが独立してバージョンアップ・修正可能
- 将来的に共通 Construct が 5+ に増えた場合は npm private package (CodeArtifact) を検討

---

## 2. 概念マッピング (Terraform -> CDK)

| Terraform | CDK | 役割 |
|-----------|-----|------|
| module | Construct (L3) | 再利用可能なリソースグループ |
| environments/ dir | Stage | 環境レベルのグループ化 |
| main.tf (root module) | Stack | CloudFormation Stack = デプロイ単位 |
| terraform_remote_state | SSM Parameter Store | クロススタック参照 |
| variables.tf | Config object (TypeScript) | 入力パラメータ |
| for_each on modules | TypeScript for loop | レーンパターン |
| default_tags | CDK Aspects | クロスカッティング関心事 |
| secret.auto.tfvars | SSM SecureString / Secrets Manager | 秘匿値 (CDK 外で事前作成、参照のみ) |
| terraform/shared + terraform/project | 別リポジトリ (shared / project) | SSM 命名規則のみが IF |

---

## 3. App / Stage / Stack / Construct 階層

```
[aws-infra-shared リポジトリ]
App (bin/app.ts)
  └── SharedStage (per-env)
        ├── NetworkStack
        │     ├── KMS Keys (直書き)
        │     └── SharedVpc          ← TGW ID, PHZ IDs を SSM に書込
        └── IamStack                 (直書き、Construct 不使用)

[aws-ecs-template リポジトリ (project)]
App (bin/app.ts)
  └── ProjectStage (per-env)
        ├── FoundationStack
        │     ├── KMS Keys (直書き)
        │     ├── Logging (直書き)
        │     ├── ProjectVpc          ← SSM から TGW ID を読取
        │     └── HostedZone
        ├── DatabaseStack
        │     └── AuroraServerless
        ├── LaneStack["user"]
        │     ├── InternalAlb
        │     ├── AssetBucket
        │     └── LaneDistribution
        ├── LaneStack["admin"]
        │     ├── InternalAlb
        │     ├── AssetBucket
        │     └── LaneDistribution
        ├── ApplicationStack
        │     └── Application (ECS + ECR + IAM 統合)
        └── CicdStack (optional)
              └── DeployPipeline
```

### Stack 依存関係 (デプロイ順 / 削除逆順)

```
[shared リポ]                 [project リポ]
NetworkStack ────SSM────> FoundationStack
IamStack                      │
                              ├──SSM──> DatabaseStack
                              ├──SSM──> LaneStack["user"]
                              ├──SSM──> LaneStack["admin"]
                              └──SSM──> ApplicationStack
                                          └──SSM──> CicdStack (optional)
```

- `──SSM──>`: SSM Parameter Store 経由 (疎結合、独立デプロイ可能)
- リポジトリ間もリポジトリ内 Stack 間も全て SSM で統一
- デプロイ順: 左 → 右、上 → 下
- 削除順: 逆方向

### リポジトリ分離の理由

1. **ライフサイクル分離**: shared は稀にしか変更しない。project は頻繁に変更
2. **権限分離**: shared と project で異なる IAM 権限でデプロイ
3. **チーム分離**: 将来的に shared を別チームが管理する可能性
4. **プロジェクト増殖**: project リポジトリはテンプレートとしてコピー。shared はアカウントに 1 つ
5. **Terraform 構成との対応**: `terraform/shared` vs `terraform/project` をそのまま踏襲

### Stack 分割の判断基準

| Stack | 分割理由 |
|-------|---------|
| FoundationStack | 初回デプロイ後ほぼ変更なし (VPC, Subnet, KMS) |
| DatabaseStack | 削除保護、独立した更新頻度、機密性 |
| LaneStack (per-lane) | レーン追加/削除時の影響範囲を限定 |
| ApplicationStack | ECS/ECR/IAM はサービス追加時にまとめて変更 |
| CicdStack | オプショナル、環境によっては不要 |

---

## 4. Config 管理

### 型定義 (`lib/helpers/config-types.ts`)

```typescript
export interface AccountConfig {
  accountId: string;
  region: string;
}

export interface SharedConfig {
  account: AccountConfig;
  environment: string;
  vpcCidr: string;
  azs: string[];
  publicSubnets: Record<string, string>;   // AZ -> CIDR
  privateSubnets: Record<string, string>;
  interfaceEndpoints: string[];
  projectVpcCidrs: Record<string, string>;  // project名 -> CIDR
}

export interface LaneConfig {
  identifier: string;
}

export interface ServiceConfig {
  lane: string;
}

export interface ProjectConfig {
  account: AccountConfig;
  projectName: string;
  environment: string;
  vpcCidr: string;
  domainName: string;
  lanes: Record<string, LaneConfig>;
  services: Record<string, ServiceConfig>;
  database: {
    deletionProtection: boolean;
    skipFinalSnapshot: boolean;
  };
  enableCicd: boolean;
}
```

### 環境設定例 (`config/projects/myapp/dev.ts`)

```typescript
import { ProjectConfig } from '../../lib/helpers/config-types';

export const config: ProjectConfig = {
  account: { accountId: '111111111111', region: 'ap-northeast-1' },
  projectName: 'myapp',
  environment: 'dev',
  vpcCidr: '10.1.0.0/16',
  domainName: 'o2c.click',
  lanes: {
    user:  { identifier: 'user' },
    admin: { identifier: 'admin' },
  },
  services: {
    'user-api':  { lane: 'user' },
    'admin-api': { lane: 'admin' },
  },
  database: { deletionProtection: false, skipFinalSnapshot: true },
  enableCicd: false,
};
```

### CLI でのコンテキスト指定

```bash
# --- shared ---
cd cdk/shared/
npx cdk synth -c env=dev
npx cdk diff -c env=dev
npx cdk deploy -c env=dev

# --- project ---
cd cdk/project/
npx cdk synth -c env=dev
npx cdk diff -c env=dev
npx cdk deploy -c env=dev

# 単一 Stack のみ
npx cdk deploy -c env=dev "myapp-dev/Lane-user"
```

`-c project=` は不要。config の `projectName` で決定される。
実運用時 (別リポジトリ) も同じコマンド体系。

---

## 5. クロススタック参照

### 同一 Stage 内 (Stack 間): SSM Parameter Store で統一

同一 Stage 内でも SSM 経由を基本とする。CDK のプロパティ渡し (`Fn::ImportValue`) は便利だが、
Stack 間に暗黙的な削除順序制約を作るため、運用中の Stack 削除・再作成でハマるリスクがある。

```typescript
// FoundationStack: SSM に書込
new ssm.StringParameter(this, 'VpcId', {
  parameterName: `/${projectName}/${env}/infra/vpc-id`,
  stringValue: vpc.vpcId,
});

// DatabaseStack: SSM から読取
const vpcId = ssm.StringParameter.valueForStringParameter(
  this, `/${projectName}/${env}/infra/vpc-id`
);
```

これにより各 Stack が独立してデプロイ・削除可能になる。

### Shared -> Project (App 間): SSM Parameter Store

```
SSM パラメータ命名規則:
  /shared/<env>/infra/<param>              # shared → project (非秘匿)
  /<project>/<env>/infra/<param>           # project Stack 間 + ecspresso (非秘匿)
  /<project>/<env>/secrets/<param>         # 秘匿値 (CDK 外で作成、参照のみ)
```

**SharedNetworkStack (書込)**:
```typescript
new ssm.StringParameter(this, 'TgwId', {
  parameterName: `/shared/${env}/infra/transit-gateway-id`,
  stringValue: tgw.transitGatewayId,
});
```

**FoundationStack (読取)**:
```typescript
const tgwId = ssm.StringParameter.valueForStringParameter(
  this, `/shared/${env}/infra/transit-gateway-id`
);
```

### SSM パラメータ一覧

| パラメータ | Writer | Reader | 用途 |
|-----------|--------|--------|------|
| `/shared/<env>/infra/transit-gateway-id` | SharedNetworkStack | FoundationStack | TGW Attachment |
| `/shared/<env>/infra/private-subnet-cidrs` | SharedNetworkStack | FoundationStack | SG ルール |
| `/shared/<env>/infra/endpoint-phz-zone-ids` | SharedNetworkStack | FoundationStack | Route53 PHZ |
| `/<project>/<env>/infra/vpc-id` | FoundationStack | DatabaseStack, LaneStack, ApplicationStack | VPC 参照 |
| `/<project>/<env>/infra/private-subnet-ids` | FoundationStack | DatabaseStack, LaneStack, ApplicationStack | サブネット配置 |
| `/<project>/<env>/infra/sg/<name>/id` | FoundationStack | DatabaseStack, LaneStack, ApplicationStack | SG 参照 |
| `/<project>/<env>/infra/kms/<key>/arn` | FoundationStack | DatabaseStack, LaneStack, ApplicationStack | 暗号化 |
| `/<project>/<env>/infra/ecs-cluster-name` | ApplicationStack | ecspresso | クラスタ名 |
| `/<project>/<env>/infra/ecr/<service>/url` | ApplicationStack | ecspresso | ECR URL |
| `/<project>/<env>/infra/task-execution-role-arn` | ApplicationStack | ecspresso | タスク実行ロール |
| `/<project>/<env>/infra/task-role/<service>/arn` | ApplicationStack | ecspresso | タスクロール |
| `/<project>/<env>/infra/target-group/<lane>/arn` | LaneStack | ecspresso | ALB TG |

### ecspresso 連携

Terraform の tfstate plugin を SSM plugin に変更:

```yaml
# ecspresso.yml
plugins:
  - name: ssm
    config:
      prefix: /<project>/<env>/infra/
```

ecspresso は `/infra/` プレフィックスのみ参照。`/secrets/` への不要なアクセス権を持たない。

---

## 6. レーンパターン

ProjectStage 内で TypeScript ループにより per-lane Stack を生成:

```typescript
for (const [laneName, laneConfig] of Object.entries(config.lanes)) {
  new LaneStack(this, `Lane-${laneName}`, {
    lane: laneName,
    foundationStack: foundation,
    // ...
  });
}
```

### レーン追加手順

1. config ファイルに lane を追加:
   ```typescript
   lanes: {
     user:  { identifier: 'user' },
     admin: { identifier: 'admin' },
     api:   { identifier: 'api' },      // 追加
   },
   ```
2. `npx cdk deploy` で新しい `LaneStack["api"]` が自動生成

---

## 7. 運用ワークフロー

### 新プロジェクト追加

1. `cdk/project/` (テンプレート) をコピーして新リポジトリ作成
2. `config/environments/dev.ts` の `projectName`, `vpcCidr` 等を変更
3. shared 側の `config/environments/dev.ts` → `projectVpcCidrs` に新 CIDR を追加
4. shared をデプロイ (TGW ルート更新): `cd cdk/shared && npx cdk deploy -c env=dev`
5. project をデプロイ: `cd <new-project> && npx cdk deploy -c env=dev`

**project 側はテンプレートコピー + config 変更のみ。**

### 新環境追加

1. shared: `config/environments/stg.ts` を作成してデプロイ
2. project: `config/environments/stg.ts` を作成してデプロイ

**コード変更不要。config のみ。**

---

## 8. CDK Aspects (ガバナンス)

### Tagging (Terraform default_tags 相当)

```typescript
// Stage 適用レベル
cdk.Aspects.of(stage).add(new StandardTags(config.projectName, config.environment));
```

Tags: `ProjectName`, `Environment`, `ManagedBy=cdk`

### Encryption

全 S3 バケット、RDS、CloudWatch Logs の KMS 暗号化を Aspect で検証。
違反時に `Annotations.of(node).addError()` でシンセシス失敗。

---

## 9. テスト戦略

| レベル | 対象 | ツール | 実行タイミング |
|--------|------|--------|---------------|
| Unit | Construct 単位 | Jest + assertions | 毎コミット |
| Snapshot | Stack 単位 | Jest + toMatchSnapshot | 毎コミット |
| Aspect | ポリシー検証 | Jest | 毎コミット |
| Integration | 実環境デプロイ | integ-tests (将来) | リリース前 |

```typescript
// Unit test 例
test('AssetBucket creates versioned encrypted S3 bucket', () => {
  const stack = new cdk.Stack();
  new AssetBucket(stack, 'Test', { lane: 'user', ... });
  const template = Template.fromStack(stack);
  template.hasResourceProperties('AWS::S3::Bucket', {
    VersioningConfiguration: { Status: 'Enabled' },
  });
});
```

### テスト補足

- **Snapshot テストは控えめに**: 頻繁に変更される Stack (LaneStack 等) は assertions 中心。
  CDK アップグレード時にメタデータ変更で大量 diff が出ると「意図的 vs 破壊的」の判別が困難になる
- **ステートフルリソースの logical ID テスト**: Aurora, S3 バケットの logical ID が変わらないことを
  `template.hasResource()` で検証。意図しない logical ID 変更はリソース再作成 (データロス) につながる
- **Aspect テスト**: タグ付け・暗号化 Aspect が正しく動作することを独立したテストで検証

---

## 10. 秘匿値管理

### 原則: CDK/CloudFormation で秘匿値を作成しない

CDK で SSM SecureString や Secrets Manager シークレットを**作成**すると、
CloudFormation テンプレート・変更セット・CloudTrail に初期値が**平文で記録**される。
これを避けるため、秘匿値は CDK 外で事前作成し、CDK は参照のみとする。

### 秘匿値の分類と管理方法

| 秘匿値 | 管理方法 | CDK での扱い |
|--------|---------|-------------|
| DB マスターパスワード | RDS managed secret (`manageMasterUserPassword: true`) | CDK で設定可 (RDS が Secrets Manager に自動保存) |
| Django secret key | SSM SecureString (事前作成) | `fromSecureStringParameterAttributes()` で参照のみ |
| CloudFront 署名鍵 | Secrets Manager (事前作成) | `Secret.fromSecretNameV2()` で参照のみ |
| API キー等 | SSM SecureString or Secrets Manager (事前作成) | 参照のみ |

### 禁止事項

- `config/*.ts` に秘匿値を**絶対に含めない**
- CDK コード内で `SecureString` の `value` を指定しない
- `cdk.out/` を CI アーティファクトとして保存する場合は暗号化 S3 バケットを使用

### 環境構築時の秘匿値セットアップ手順

CDK deploy より前に実行:

```bash
# Django secret key
aws ssm put-parameter \
  --name "/<project>/<env>/secrets/django-secret-key" \
  --type SecureString \
  --value "$(openssl rand -base64 50)" \
  --key-id alias/<project>-<env>-secrets

# CloudFront 署名鍵 (必要な場合のみ)
aws secretsmanager create-secret \
  --name "/<project>/<env>/secrets/cloudfront-signing-key" \
  --kms-key-id alias/<project>-<env>-secrets \
  --secret-string file://private-key.pem
```

---

## 11. CloudFront us-east-1 証明書

### 状況: 管理アカウント確認待ち (#16)

クライアント環境のセキュリティルールにより、CDK の `crossRegionReferences: true` は **使用不可**。
代替方針は管理アカウントへの問い合わせ結果を待って決定する。

### 抵触するルール

#### 共通禁止事項 #2 (`docs/security_gide_template.md` L95)

> 情報の機密性を担保するため、日本リージョン以外でAWSリソースを作成することの禁止

us-east-1 への ACM 証明書作成は原則禁止。

#### 例外的記述 (`docs/security_gide_template.md` L982-985, セクション 3.3.16)

> ACMでCloudFront用証明書を発行しバージニア北部リージョンで発行した証明書の更新監視を行う場合、
> CloudWatchやEventBridgeなどのサービスが標準環境の「国外リージョンへのリソース作成を禁止」の
> 統制により利用不可能である。

→ ACM 証明書発行そのものは例外的に許可されている前提で書かれている
→ ただし監視系サービス (CloudWatch, EventBridge) は us-east-1 で使えない

### CDK `crossRegionReferences: true` が抵触する点

CDK が自動生成する以下のリソースが全て共通禁止 #2 に抵触するため、**使用不可**:

| 自動生成リソース | 抵触ルール |
|---------------|-----------|
| us-east-1 の Lambda Custom Resource | 共通禁止 #2 |
| us-east-1 の CloudFormation 補助 Stack | 共通禁止 #2 |
| us-east-1 の SSM Parameter | 共通禁止 #2 |
| us-east-1 の bootstrap stack (`cdk-hnb659fds-*`) | 共通禁止 #2 + サービスロール指定なし作成 (2.2.20 #2) |

### 代替方針 (管理アカウント確認後に確定)

候補:

- **A**: 管理アカウントが us-east-1 ACM 証明書を発行 → ARN を config にハードコード or SSM 参照
- **B**: us-east-1 用の独立した CFn テンプレートを別途手動デプロイ → ARN を config にハードコード
- **C**: 標準環境の CFn テンプレートで証明書発行 → ARN を引き渡し

開発環境 (`deployMode: cdk-deploy`) では `crossRegionReferences: true` を使用可能。
クライアント環境 (`deployMode: template-only`) では上記いずれかの方針で対応する。

### 管理アカウントへの確認事項 (#16)

1. us-east-1 での ACM 証明書発行は個別許可されているか
2. 許可されているリソースは ACM 証明書のみか、付随リソース (S3, Lambda 等) も含むか
3. 証明書発行手段 (手動コンソール / CFn テンプレート / 標準環境提供テンプレート)
4. 証明書 ARN の引き渡し手順 (標準環境提供 or 全社/部門システム担当者側で取得)

---

## 12. cdk.json / cdk.context.json

### cdk.json テンプレート

```json
{
  "app": "npx ts-node bin/app.ts",
  "watch": {
    "include": ["**"],
    "exclude": ["node_modules", "cdk.out", "test"]
  },
  "context": {
    "@aws-cdk/aws-lambda:recognizeLayerVersion": true,
    "@aws-cdk/core:checkSecretUsage": true,
    "@aws-cdk/core:stackRelativeExports": true,
    "@aws-cdk/aws-s3:createDefaultLoggingPolicy": true,
    "@aws-cdk/aws-ecs:removeDefaultDesiredCount": true,
    "@aws-cdk/aws-rds:lowercaseDbIdentifier": true,
    "@aws-cdk/aws-kms:reduceCrossAccountRegionPolicyScope": true
  }
}
```

- 各リポジトリに `cdk.json` があり、`app` は `bin/app.ts` を指す
- shared / project で共通のフォーマット

### cdk.context.json

- **Git にコミットする** (CDK 公式推奨)
- `cdk synth` 時の VPC lookup 等の結果をキャッシュし、合成の決定性を保証
- context が古くなったら `cdk context --reset` で再取得

### CDK バージョン管理

```json
{
  "dependencies": {
    "aws-cdk-lib": "2.180.0"
  }
}
```

- **exact pin** (キャレットなし) でバージョンを固定
- アップグレードは明示的な PR で実施 (Renovate/Dependabot で CDK のみ個別 PR)
- snapshot テストでテンプレート差分を検知

---

## 13. Terraform からの移行方針

### Phase 1: CDK コード開発
- Terraform と並行して CDK コードを開発
- `cdk synth` + スナップショットテストで CloudFormation テンプレートを検証

### Phase 2: 新環境で CDK デプロイ
- 新しい環境 (例: test) を CDK で先にデプロイして検証

### Phase 3: 既存環境の移行
- `cdk import` で既存リソースを CloudFormation Stack にインポート
- または、新アカウントで CDK ゼロデプロイ → DNS 切替

### Phase 4: ecspresso 移行
- tfstate plugin → ssm plugin へ変更 (サービス単位で段階的に)

### Phase 5: CDK Pipelines 導入 (将来)
- CDK インフラ自体の CI/CD に CDK Pipelines (`aws-cdk-lib/pipelines`) を導入
- `SharedStage` / `ProjectStage` の構造が `pipeline.addStage()` に対応しているため導入障壁は低い
- 複数環境へのデプロイに Wave/Stage 機能を活用
- 本番環境への Manual Approval ゲートを追加

---

## 14. 依存パッケージ

```json
{
  "dependencies": {
    "aws-cdk-lib": "^2.x",
    "constructs": "^10.x"
  },
  "devDependencies": {
    "aws-cdk": "^2.x",
    "typescript": "^5.x",
    "jest": "^29.x",
    "ts-jest": "^29.x",
    "@types/jest": "^29.x",
    "@types/node": "^20.x"
  }
}
```

サードパーティ Construct ライブラリは初期段階では不要。全て `aws-cdk-lib` で実装。
