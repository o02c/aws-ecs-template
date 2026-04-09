# Accepted Risks / Design Decisions

セキュリティレビューにおいて検出された指摘事項のうち、AWS仕様上の制約やアーキテクチャ上の判断により意図的に対応しないこととした項目について、その根拠とリスク受容の判断を記載する。

各項目には、[セキュリティガイド](./security_gide_template.md) における関連条項を明記する。

---

## 1. SHA-1 in CloudFront Signed URLs

### 関連ガイド条項

- **2.2.2. Amazon CloudFront > 手動運用で統制を行う禁止行為**
  - 暗号化アルゴリズムに関する一般的なセキュリティ要件との潜在的な抵触

### 指摘内容

CloudFront署名付きURLにおいてRSA-SHA1が使用されている。SHA-1は暗号学的に非推奨とされているアルゴリズムである。

### 根拠

CloudFront署名付きURLは、AWSの仕様としてRSA-SHA1による署名が**必須**である。代替のアルゴリズムは提供されていない。

> Hash the policy statement using SHA-1, and sign the hash using RSA and the private key

- [Amazon CloudFront Developer Guide - Creating a signed URL using a custom policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-creating-signed-url-custom-policy.html)

### リスク受容

- **受容レベル**: Low
- AWSプロトコル上の制約であり、利用者側で代替手段を選択できない。AWS側の仕様変更を待つ以外に対応方法はない。

---

## 2. S3 Encryption: AES256 (SSE-S3) for logging and CI/CD buckets

### 関連ガイド条項

- **2.2.16. Amazon S3 > 1) A) S3に関する共通的な禁止事項**
  - 「KMSキーによって暗号化されていないS3バケットを作成することの禁止」に対する例外

### 指摘内容

ロギング用バケット (`*-access-logs-*`) およびCI/CDアーティファクト用バケットにおいて、KMS (SSE-KMS) ではなくAES256 (SSE-S3) による暗号化が使用されている。

### 根拠

ALBアクセスログおよびCloudFront標準ログの配信先S3バケットは、AWSの仕様により**SSE-S3が必須**である。SSE-KMSを設定した場合、ログ配信が失敗する。

> Server-side encryption: Amazon S3-managed keys (SSE-S3)

- [Elastic Load Balancing - Enable access logging](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html)

> For standard logging, CloudFront doesn't support SSE-KMS encryption for the S3 bucket.

- [Amazon CloudFront Developer Guide - Configuring standard logging](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html)

CI/CDアーティファクト用バケットについては、ロギングバケットとの一貫性の確保、およびCodePipelineアーティファクト暗号化固有の制約を考慮し、AES256 (SSE-S3) を採用している。

### リスク受容

- **受容レベル**: Low
- SSE-S3による保存時暗号化は提供されている。カスタマーマネージドキーによる鍵ローテーション制御は利用できないが、AWSマネージドキーによる暗号化は有効である。ガイド条項の趣旨（保存時暗号化の確保）は満たしている。

---

## 3. Inspector: ECR only, not ECS runtime

### 関連ガイド条項

- **2.2.12. Amazon Inspector > 2) 手動運用で統制を行う禁止行為**
  - 「Inspectorの脆弱性チェック対象外のインスタンスがあることの禁止」— EC2を対象とした条項だが、ECSランタイムスキャンにも同趣旨が適用される

### 指摘内容

Amazon InspectorによるスキャンがECRコンテナイメージのみを対象としており、ECS Fargateランタイムスキャンが有効化されていない。

### 根拠

ECSランタイムスキャンはFireLensサイドカー構成と合わせて有効化する予定であり、issue [#5](https://github.com/o02c/aws-ecs-template/issues/5) にて追跡管理されている。

### リスク受容

- **受容レベル**: Medium
- ランタイム脆弱性検出に一時的なギャップが存在する。ECRイメージスキャンによりデプロイ前の脆弱性検出は確保されているが、実行時の脆弱性検出はFireLens導入まで対応されない。
- **解消予定**: issue [#5](https://github.com/o02c/aws-ecs-template/issues/5) 対応時

---

## 4. DNS Firewall disabled

### 関連ガイド条項

- **2.2.15. Amazon Route 53 Resolver DNS Firewall > 1) システム的な統制がかけられている禁止行為**
  - 「標準環境で作成したドメインリスト・ルールグループの変更・削除を禁止」— 本システムではそもそもDNS Firewallを作成していないため、変更・削除の禁止は該当しないが、DNS Firewallによる保護が提供されていない点が潜在的な逸脱
- **2.2.19. Amazon VPC > 1) システム的な統制がかけられている禁止行為**
  - DNS exfiltration対策としてのネットワーク制御に関連

### 指摘内容

Route 53 Resolver DNS Firewallが無効化（コメントアウト）されている。

### 根拠

本システムのVPCはプライベートサブネットのみで構成されており、インターネットへの直接のエグレスパスを持たない。ECSタスクはVPCエンドポイント経由でのみAWSサービスと通信しており、DNS exfiltrationのリスクは極めて限定的である。コスト対効果の観点から、現時点では無効化としている。

NATゲートウェイ経由での外部APIアクセスが必要となった時点で再評価を行う。

### リスク受容

- **受容レベル**: Low
- VPCエンドポイント経由の通信のみであり、DNS経由のデータ流出リスクは最小限に抑えられている。外部通信要件の追加時に再度有効化を検討する。

---

## 5. シークレット管理に SSM Parameter Store を使用

### 関連ガイド条項

- **2.2.33. AWS Secrets Manager > 2) 手動運用で統制を行う禁止行為**
  - 「Secrets Managerを用いずにパスワード等のシークレットを管理することの禁止」

### 指摘内容

パスワード等のシークレット管理に Secrets Manager ではなく SSM Parameter Store (SecureString) を使用している。

### 根拠

- 自動ローテーションが不要なユースケースであり、Secrets Manager のローテーション機能を必要としない
- SSM Parameter Store SecureString は KMS カスタマーマネージドキーで暗号化され、保存時・転送時の暗号化は Secrets Manager と同等
- ECS タスク定義からの参照方式も Secrets Manager と同様に `valueFrom` で対応可能
- コスト面で Parameter Store が有利（Standard パラメータは無料）

### リスク受容

- **受容レベル**: Low
- セキュリティ上の実質的な差異はない。ガイドライン条項の趣旨（平文でのシークレット管理禁止、一元管理の実現）は Parameter Store でも満たされる。
- **対応:** 標準環境管理者に事前確認の上、承認を得ること
