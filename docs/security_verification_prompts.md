# セキュリティ禁止事項 検証プロンプト一覧

> 各検証項目に対して、サブエージェントに渡すプロンプトを記載する。
> 「標準環境リソースの変更・削除禁止」系はSCPで強制されるため、ここでは **自分たちが作成するリソースの設定** が禁止事項に抵触しないかを検証する項目のみを対象とする。

---

## 検証1: CloudFront + WAF の紐付け

**対応禁止事項:** CloudFront 2.2.2 #1, #2

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、以下を検証してください。

1. CloudFront ディストリビューションが作成されているか
2. CloudFront に WAF (Web ACL) が紐付けられているか（web_acl_id の設定）
3. CloudFront のオリジンが ALB 等の Web アプリケーションと正しく紐づいているか

対象ファイル: terraform/project/modules/cdn/ および terraform/project/modules/storage/
結果を「準拠 / 非準拠 / 未実装」で報告し、非準拠の場合は具体的な修正案を提示してください。
```

---

## 検証2: S3 バケットの暗号化・SSL強制・アクセスログ

**対応禁止事項:** S3 2.2.16 A-#3, C-#6, C-#7

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、全ての S3 バケットリソースについて以下を検証してください。

1. KMS カスタマーマネージドキーによる暗号化が設定されているか（aws_kms_key）
2. バケットポリシーで SSL (aws:SecureTransport) を要求しているか
3. サーバーアクセスログが有効化されているか（logging 設定）
4. パブリックアクセスブロック設定が有効か

対象ファイル: terraform/project/modules/storage/ および terraform/project/modules/logging/ 配下の全 .tf ファイル
結果を各バケットごとに「準拠 / 非準拠」で報告し、非準拠の場合は具体的な修正案を提示してください。
```

---

## 検証3: VPC セキュリティグループのルール

**対応禁止事項:** VPC 2.2.19 #8

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、全ての aws_security_group_rule リソースについて以下を検証してください。

1. cidr_blocks に "0.0.0.0/0" を指定した無制限のインバウンドトラフィック許可がないか
2. ポート範囲 0-65535 の全ポート開放がないか
3. protocol = "-1" (全プロトコル) かつ cidr_blocks = "0.0.0.0/0" の組み合わせがないか

対象ファイル: terraform/project/modules/ 配下の全 security_group*.tf ファイル
結果を各ルールごとに「準拠 / 非準拠」で報告してください。
```

---

## 検証4: VPC フローログの有効化

**対応禁止事項:** VPC 2.2.19 #2

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、以下を検証してください。

1. VPC に対して VPC フローログ (aws_flow_log) が設定されているか
2. フローログの出力先が適切に設定されているか（S3 or CloudWatch Logs）

対象ファイル: terraform/project/modules/network/ 配下の全 .tf ファイル
結果を「準拠 / 非準拠 / 未実装」で報告してください。
```

---

## 検証5: VPC エンドポイントポリシーの Deny 設定

**対応禁止事項:** VPC 2.2.19 #14

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、全ての aws_vpc_endpoint リソースについて以下を検証してください。

1. VPC エンドポイントにポリシーが設定されているか
2. ポリシーに他AWSアカウントのプリンシパルを拒否する DenyOtherAwsAccountPrincipals の Statement が含まれているか

対象ファイル: terraform/project/modules/network/ 配下の全 .tf ファイル
結果を各エンドポイントごとに「準拠 / 非準拠」で報告してください。
```

---

## 検証6: RDS (Aurora) の暗号化・パブリックアクセス禁止

**対応禁止事項:** RDS 2.2.13 #3, #4

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、Aurora/RDS リソースについて以下を検証してください。

1. storage_encrypted = true が設定されているか
2. kms_key_id に KMS カスタマーマネージドキーが指定されているか
3. publicly_accessible = false が設定されているか（デフォルト false だが明示的かどうか）

対象ファイル: terraform/project/modules/db/ 配下の全 .tf ファイル
結果を「準拠 / 非準拠」で報告し、非準拠の場合は具体的な修正案を提示してください。
```

---

## 検証7: IAM ポリシーの権限範囲

**対応禁止事項:** IAM 2.2.26 #6, #7

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、全ての IAM ポリシー (aws_iam_policy, aws_iam_role_policy, aws_iam_policy_document) について以下を検証してください。

1. Action と Resource の両方に "*" を指定した完全な管理権限がないか
2. IAM ロールの trust policy (assume_role_policy) で外部エンティティ（他AWSアカウント等）へのアクセス許可がないか
3. Principal に外部アカウント ID やワイルドカードが含まれていないか

対象ファイル: terraform/project/modules/ 配下の全 .tf ファイル（特に app/, cicd/ モジュール）
結果を各ポリシーごとに「準拠 / 非準拠」で報告してください。
```

---

## 検証8: ECR の VPC エンドポイント経由アクセス

**対応禁止事項:** ECR 2.2.8 #1

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、以下を検証してください。

1. ECR 用の VPC エンドポイント (ecr.api, ecr.dkr) が作成されているか
2. ECS タスクが ECR からイメージを pull する際に VPC エンドポイント経由となる構成になっているか（プライベートサブネット + VPC エンドポイント）

対象ファイル: terraform/project/modules/network/ および terraform/project/modules/app/
結果を「準拠 / 非準拠 / 未実装」で報告してください。
```

---

## 検証9: KMS 暗号化の網羅性

**対応禁止事項:** 共通 2.1 #5, EBS 2.2.6 #1, RDS 2.2.13 #4, S3 2.2.16 A-#3

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、データを保管する全てのリソースについて KMS カスタマーマネージドキーによる暗号化が設定されているか検証してください。

確認対象:
1. S3 バケット → server_side_encryption_configuration で aws:kms が設定されているか
2. Aurora クラスター → storage_encrypted + kms_key_id
3. CloudWatch Logs → kms_key_id
4. ECR リポジトリ → encryption_configuration

対象ファイル: terraform/project/modules/ 配下の全 .tf ファイル
結果を各リソースごとに「準拠 / 非準拠」で報告してください。
```

---

## 検証10: Secrets Manager によるシークレット管理

**対応禁止事項:** Secrets Manager 2.2.33 #1

**プロンプト:**
```
このリポジトリの Terraform コードおよび ecspresso 設定を調査し、以下を検証してください。

1. データベースパスワード等のシークレットが Secrets Manager で管理されているか
2. ECS タスク定義でシークレットの参照に Secrets Manager ARN を使っているか（平文での環境変数設定がないか）
3. ハードコードされたパスワードやトークンがコード内に存在しないか

対象ファイル: terraform/project/modules/db/, terraform/project/modules/app/, ecs/ 配下の全ファイル
結果を「準拠 / 非準拠 / 未実装」で報告してください。
```

---

## 検証11: DNS Firewall の設定

**対応禁止事項:** Route 53 DNS Firewall 2.2.15 #1, #2

**プロンプト:**
```
このリポジトリの Terraform コードを調査し、以下を検証してください。

1. Route 53 Resolver DNS Firewall のルールグループが作成されているか
2. ルールグループが VPC に関連付けられているか
3. AWS マネージドドメインリスト（AWSManagedDomainsAggregateThreatList 等）が使われているか

対象ファイル: terraform/project/modules/dns_firewall/ 配下の全 .tf ファイル
結果を「準拠 / 非準拠 / 未実装」で報告してください。
```

---

## 検証12: CloudFormation スタック作成時のサービスロール

**対応禁止事項:** CloudFormation 2.2.20 #2

**プロンプト:**
```
このリポジトリの構成では Terraform を使用していますが、以下を確認してください。

1. Terraform 内で aws_cloudformation_stack リソースを使用している箇所があるか
2. ある場合、iam_role_arn (サービスロール) が指定されているか
3. ECS クラスターやサービスの作成が CLI/ecspresso 経由であり、CloudFormation を経由しない構成になっているか

対象ファイル: terraform/project/ および ecs/ 配下の全ファイル
結果を「準拠 / 該当なし」で報告してください。
```

---

## 使い方

各プロンプトをサブエージェント（Explore タイプ）に渡して検証を実行する。
実行例:

```
Agent(subagent_type="Explore", prompt="<上記プロンプト>")
```

全検証が完了したら、非準拠項目をまとめて対応計画を策定する。
