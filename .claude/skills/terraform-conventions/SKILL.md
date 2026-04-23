---
name: terraform-conventions
description: terraform/ 配下の規約。モジュール構成・命名・for_each・SG パターン・マルチレーン・IAM / KMS / セキュリティ要件など。Use when editing any file under terraform/.
---

# Terraform Conventions (aws-ecs-template)

`terraform/` 配下を触るとき必ず参照する規約。CLAUDE.md と `docs/security_prohibitions.md`、実コードから抽出。

## Scope

- 扱う：ディレクトリ構成、命名、for_each、SG パターン、タグ、ファイル分割、Backend、一般 IAM ポリシー記述規則、セキュリティ必須要件。
- 扱わない：IAM ユーザー / グループ / スイッチロール設計 → **`iam-design` skill を参照**。deploy / destroy 手順 → **`deploy-lifecycle` skill を参照**。

## 1. ディレクトリ構成

```
terraform/
  shared/                  # 1 AWS アカウントに 1 つ
    environments/<env>/    # main.tf / locals.tf / variables.tf / outputs.tf / versions.tf / providers.tf
    modules/<name>/        # リソース種別ごとの .tf で構成
  project/                 # プロジェクトごとにコピーするテンプレート
    environments/<env>/
    modules/<name>/
```

- `main.tf` は **`environments/` 配下のみ**。モジュール内では作らない。
- `versions.tf` は environments と「provider alias が必要なモジュール」のみ置く（`modules/cdn/versions.tf` のように `configuration_aliases = [aws.us_east_1]` を宣言するケース）。
- project は shared を `terraform_remote_state` で参照。shared を先に apply。

### ファイル命名・分割

- ファイル名は **含まれるリソースを明示**。例：`ecs_cluster.tf` / `aurora.tf` / `s3.tf` / `vpc.tf` / `subnets.tf` / `route_tables.tf` / `security_groups.tf` / `security_group_rules.tf` / `vpc_endpoints.tf` / `vpc_flow_logs.tf`。
- 分割の目安：**100 行超 or 3 種類以上のリソース混在**。ただし同一論理グループ（例：ALB + TargetGroup + Listener、IAM Role + そのインラインポリシー群）は凝集優先でまとめてよい（`cdn/cloudfront.tf` 154 行、`app/iam.tf` 165 行は許容例）。
- 一方で「IAM ロールとポリシーを役割ごとに分ける」ときはファイルを分ける（`cicd/iam_codebuild.tf` / `iam_codepipeline.tf` / `iam_eventbridge.tf`）。
- **機能本体リソースと補助リソース（IAM role / CloudWatch Logs / Firehose など）は分ける**。
- **補助リソースのファイル名は "その AWS サービスのリソースがモジュール内に複数あるか" で決める**：
  - 1 つだけなら **AWS サービス名のみ**：`cloudwatch.tf` / `iam.tf` / `firehose.tf`
  - 複数あるなら purpose を付ける：`iam_codebuild.tf` / `iam_codepipeline.tf` / `iam_eventbridge.tf`
  - 例：VPC Flow Logs の場合、本体は `vpc_flow_logs.tf`、補助 IAM Role が 1 つなら `iam.tf`、Log Group が 1 つなら `cloudwatch.tf`（`iam_flow_log.tf` / `cloudwatch_flow_log.tf` のような purpose 付き命名は **不要**）。

## 2. 命名規則

### 物理名（リソース本体の name）

- `<ProjectName>-<Environment>-<identifier>` 形式。
- identifier には **AWS サービス名も短縮形も含めない**。リソースタイプは AWS 側で分かる。
  - NG：`myapp-prod-ecs-api` / `myapp-prod-api-rt` / `myapp-prod-web-sg` / `myapp-prod-igw`
  - OK：`myapp-prod-api` / `myapp-prod-public` / `myapp-prod-web`
- shared / project の区別は **`project_name` 側で表現**する。各リソースの Name に `-shared-` を挟まない。
- レーン別は `-<lane>` を付ける（例：`myapp-dev-user`、`myapp-dev-user-assets`）。

### リソース論理名（Terraform 側の識別子）

判断基準：**モジュール内で同じ AWS リソースタイプが何個あるか**。

- **1 種類しかない → `"this"`**（`for_each` で複数生成されていても同じ）
  - 例：`aws_vpc "this"`、`aws_ecs_cluster "this"`、`aws_lb "this"`、`aws_rds_cluster "this"`
  - for_each 例：`aws_security_group "this" { for_each = var.security_groups }`（`network/security_groups.tf:5`）、`aws_kms_key "this" { for_each = local.keys }`
- **同タイプが複数ある → 役割を表す名前**
  - 別インスタンス：`aws_iam_role "task_execution"` + `aws_iam_role "task"`（`app/iam.tf`）、`aws_security_group "this"` + `"vpce"`（`shared/network`）
  - サブカテゴリ：`aws_vpc_endpoint "gateway"` + `"interface"`、`aws_subnet "private"` / `"public"`
- `for_each` の key は「インスタンス識別子」として渡す値（lane / service / purpose）、論理名は「役割カテゴリ」。混同しない。

## 3. タグ

- provider の `default_tags` で `ProjectName` / `Environment` / `ManagedBy = "terraform"` を設定。
- 個別リソースは **`Name` のみ追加**。default_tags と重複させない。
- `us_east_1` エイリアスにも同じ `default_tags` を必ず書く。

## 4. コードスタイル

- セクション罫線：`# ` + `-` を 80 個。既存ファイル（例 `shared/modules/network/vpc.tf`）から copy-paste が確実。

  ```hcl
  # --------------------------------------------------------------------------------
  # Section Name
  # --------------------------------------------------------------------------------
  ```

- コメントは `#` のみ（`//` 不可）。
- **`for_each` 必須・`count` 禁止**。条件付きリソースは `for_each = cond ? { k = v } : {}` や `dynamic` ブロックで表現。
- `variable` / `output` は **使うときのみ** 定義。`description` と `type` 必須。
- outputs はコレクションなら map 出力にする：`{ for k, v in aws_... : k => v.arn }`（例：`module.network.security_group_ids`、`module.app.task_role_arns`）。

### Variable の `default` について（厳禁）

**結論**：`variable` に `default` は書かない。

**判断ツリー**：

| その値は… | 置き場所 |
|---|---|
| 環境で変える可能性がある（retention / capacity / TTL / feature flag など） | `environments/<env>` で明示的に渡す（default 禁止） |
| 絶対に変わらない定数（AWS API 制約、業界標準） | モジュール内で **ハードコード**（`variable` にしない） |
| モジュール内で複数箇所に使う内部値 | `locals` で定義 |

**なぜ**：`default` を書くと、`environments/<env>` を読んでも「その値が何か」が分からない。モジュール側に埋もれた default が実行時挙動を左右すると、PR レビューで見落とされ、環境差分の原因究明が困難になる。「環境を読むだけで挙動が分かる」（§6 UI 原則）を壊さないため。

### `locals` の使い分け

**結論**：`locals` に置くのは **2 箇所以上で使う値だけ**。1 回しか使わない計算はリソース側にインラインで書く。

**なぜ**：`locals` は「名前付きの再利用」のための仕組み。1 箇所しか使われない値に名前を付けると、読み手は「この local はなぜ存在するのか（他でも使われているかも）」を疑って視線を飛ばすコストを払うだけ。

**例外（= locals に置かない方が良いケース）**：`split` / `slice` / `join` / 複雑な `for` で可読性が落ちる計算は、たとえ 2 箇所以上で使っていても、それぞれのリソース側にインライン展開した方がマシ。可読性を犠牲にして DRY を取ると、計算意図を追えなくなる。

### 文字列操作より resource attribute / data source

- `split` / `slice` / `join` で構築せず、`aws_vpc_endpoint.dns_entry[0].dns_name` / `data "aws_region"` / `data "aws_elb_service_account"` などで取得する。
- **region→AWS サービスアカウント ID の map はハードコードしない**。`aws_elb_service_account` / `aws_cloudfront_log_delivery_canonical_user_id` のような data source が AWS から公式提供されている。map をコードに持ち込む前に必ず `data` で取れないか確認する。AWS が後日 region を増やしたとき、map は追従しないが data source は追従する。

### 関連する設定は 1 つの構造にまとめる

同じものを 2 つの variable / local に分けて管理すると片方の追加忘れで運用事故が起きる。例：Interface Endpoint とその PHZ は 1 つの map で定義し、両方を同じ `for_each` で生成する。

### `data` の `for_each` は実体 resource に合わせる

**結論**：`data` の `for_each` は、**対応する resource の `for_each`** を基準にする。変数を直接指定しない。

**現象（違反した場合）**：`data "aws_vpc_endpoint_service" { for_each = var.interface_endpoints }` のように variable を直接使うと、後で resource 側だけフィルタを足したとき（例：「dev だけ endpoint を一部無効化」）data は元の集合を見続ける → 存在しない endpoint に対して service 情報を取りに行って失敗する。

**対策**：`for_each = aws_vpc_endpoint.interface` のように **実体 resource** を基準にする。`each.value.service_name` で resource の属性にアクセスできる。resource の生成状況に data が追従するため、削除・フィルタが両側で同期する。

**適用場面**：`data` が「別 resource の属性値を引数として問い合わせる」形のとき（DNS 名、service 名など）は必ずこのパターン。独立した data（`aws_caller_identity` / `aws_region` 等）は対象外。

### Data Sources の置き場所

- そのファイル内で使う data は **ファイル先頭**に `# Data Sources` セクションを切って書く（`cdn/cloudfront.tf:1-13`、`shared/network/vpc_endpoints.tf:1-5`）。
- environment 全体で使うものは `environments/<env>/main.tf` 冒頭に置く（`data "aws_caller_identity"`、`data "terraform_remote_state"`）。

## 5. Security Group パターン（厳守）

- **`aws_security_group` は SG 専用ファイルにしか置かない**。ingress/egress をインライン定義しない（空の SG 殻）。`network` モジュールが一元管理し、他モジュールは rule を追加する側。
- **他ファイル（`vpc_endpoints.tf` など）に SG を紛れ込ませない**。同じファイルで複数種類のリソースが混ざるとレビューで見落とされる（過去に再発したため厳守）。
- ファイル名：
  - SG と rule の数が少ないモジュールは **`security_group.tf`（単数）** 1 つにまとめて OK。
  - SG と rule の両方が複数あって分けた方が読みやすい場合は **`security_groups.tf` + `security_group_rules.tf`** の 2 分割を選んでよい。
  - いずれの場合も、SG 定義 / rule 以外のリソース（endpoint、subnet、route table など）を同じファイルに入れない、が絶対条件。
- 消費側モジュールが `aws_security_group_rule` を追加するときも、ファイル名は上記ルールに従う。
- `description` 必須（例：`"From ${each.key} ALB"`、`"HTTPS to S3 via gateway endpoint"`）。
- 参照は `source_security_group_id`、CIDR は必要時のみ、S3/VPCE は `prefix_list_ids`。
- レーン別 ALB SG は `for_each = toset([...])` で network モジュールが生成し、map 出力で公開。

## 6. マルチレーン / マルチサービス

### environments を "UI" として使う

**結論**：環境で変わる可能性がある値は、すべて `environments/<env>/` に集約する。モジュール側には `default` を置かない。

**"UI" という言葉の意味**：開発者が `environments/<env>/` を開けば「この環境では何が enabled か、どのインスタンスタイプか、retention は何日か」が **1 か所で読める** 状態を指す。モジュールを深掘りしないと挙動が分からない設計は、環境差分の追跡コストを高め、レビューも運用も重くなる。

**集約対象の例**：DB インスタンスタイプ / Aurora 容量 / retention 日数 / feature flag / CIDR / lanes 構成 / services 構成 / ログライフサイクル / cache TTL など、「dev と prod で値が違っても不思議じゃない」もの。

**3 ファイルの役割**：
- `environment.auto.tfvars`：文字列・数値の単純値（project_name、domain_name など）
- `locals.tf`：計算値 / 構造化マップ（lanes、services、subnet tiers、db_config、interface_endpoints など）
- `variables.tf`：上記を受け取る変数宣言（型定義のみ）。`default` は書かない（§4）。

### lanes / services の例

```hcl
# locals.tf
lanes    = { user = {}, admin = {} }                    # 値 object は拡張フィールド置き場
services = { user-api = { lane = "user" }, admin-api = { lane = "admin" } }
```

- `lanes` は key さえあれば動く（`keys(local.lanes)` / `each.key` で使う）。レーン固有パラメータが必要になったら value に足す（例：`{ user = {}, admin = { ip_allowlist = [...] } }`）。

### 多 tier 構造化の例（subnet / db_config など）

複数 tier を持つものは **ネストしたマップ**で environments から渡す。モジュール側は受けて `for_each` で展開：

```hcl
# locals.tf (environments側)
subnet_tiers = {
  alb = { cidr = { "ap-northeast-1a" = "10.1.1.0/24", ... } }
  ecs = { cidr = { "ap-northeast-1a" = "10.1.11.0/24", ... } }
  db  = { cidr = { "ap-northeast-1a" = "10.1.21.0/24", ... } }
}

db_config = {
  engine_version      = "16.4"
  instance_class      = "db.serverless"
  min_capacity        = 0.5
  max_capacity        = 4
  backup_retention    = 7
  deletion_protection = false
}
```

readability は最優先。ネスト深くなりすぎるなら flatten を検討。locals 側での文字列処理・複雑な `for` は避ける（読めない locals は main.tf にインラインで書く方がマシ）。

### モジュール構成

- 共有：VPC / ECS Cluster / Aurora / KMS。
- レーン別：ALB / CloudFront / S3 / ALB-SG → `module "lb" { for_each = local.lanes ... }` で呼ぶ。
- サービス別：ECS Service / Task Role / ECR / Log Group → `app` モジュールに services を渡して `for_each = var.services`。
- モジュール間で map を渡すときは `{ for lane, mod in module.storage : lane => mod.bucket_arn }` のように組み立てる。

### レーン間で挙動が分岐するとき（feature flag）

**方針：レーンごとに module を分けない**。単一 module を残し、`lanes` の value に `features` object を持たせて、必要な feature をオン/オフする。分離した module（`waf_base` / `waf_ip_restricted` のようなパターン）は §4「関連する設定は 1 つの構造にまとめる」違反 かつ DRY 違反（共通 rule が重複）になる、という結論（`temp/waf-variants/` で 3 レビュワーにより評価済み）。

```hcl
# locals.tf (environments/<env>)
lanes = {
  user  = { features = {} }                    # 空 = 全 feature off
  admin = {
    features = {
      ip_restrict  = true
      ip_allowlist = ["203.0.113.0/24"]
    }
  }
}
```

```hcl
# modules/waf/variables.tf
variable "features" {
  description = "Lane-specific WAF feature toggles"
  type = object({
    ip_restrict  = optional(bool, false)
    ip_allowlist = optional(list(string), [])
  })
}
```

```hcl
# modules/waf/waf.tf
resource "aws_wafv2_ip_set" "allowlist" {
  for_each = var.features.ip_restrict ? { enabled = true } : {}
  # ...
}

dynamic "rule" {
  for_each = var.features.ip_restrict ? { enabled = true } : {}
  content { ... }
}
```

ルール：

1. environments の `lanes` 定義を読むだけで「どの lane に何が enabled か」が一望できること（UI 性）。
2. module 側は `features` object を **1 引数として受け取る**（条件判定を caller 側の条件分岐で書かない）。
3. feature を足すときは `features` 型に optional key を追加、module 内で `dynamic` ブロックを追加する（module 増殖させない）。
4. `optional()` は **module 内 variables の型側のみ**で使う。environments の `lanes` を定義するときは **全キー明示 or `features = {}`** にして、環境ファイルを読むだけで挙動が分かる状態にする（§4 の default 禁止と一貫）。

このパターンが適用される他の例：
- CloudFront の **signing on/off**：`cdn` の features に `signing = { enabled = bool, public_key_pem = string }` を足す。無効化プロジェクトでは `signing = { enabled = false, public_key_pem = "" }`。
- **pdf 一時 URL 配信**の要否：`storage` の features に `time_limited_urls = bool` を足す。不要なら依存する IAM/Secrets 等も一切生成されない構造にする。
- **dns_firewall** 等のオプショナルセキュリティ機能：上位の `project` の `locals` で enable フラグを持ち、モジュール呼び出し自体を `for_each = var.enabled ? {this = true} : {}` で制御するのも可。

## 7. IAM のパターン

3 種類を使い分ける（実コードから抽出）：

| 用途 | 書き方 | 例 |
|---|---|---|
| AWS マネージドポリシーをアタッチ | `aws_iam_role_policy_attachment` + `arn:aws:iam::aws:policy/...` | `app/iam.tf:26-29`（TaskExecutionRolePolicy） |
| ロール専用の小さなカスタムポリシー | `aws_iam_role_policy` にインライン `jsonencode` | `app/iam.tf:33-50`（pull-through-cache） |
| 複数ロールで再利用するカスタムポリシー | `aws_iam_policy`（独立リソース） + `aws_iam_role_policy_attachment` | `db/iam_auth.tf`、`storage/iam.tf` |

- `security_prohibitions.md` 2.2.26-7 は IAM **identity policy**（User / Role / Group にアタッチされるポリシー）において Allow 文で **`Resource` または `Action` に `"*"` 単独を付与することを禁止**する（「リソースとアクションそれぞれに」の厳格解釈を採用）。`Action = "*"` 単独も、`Resource = "*"` 単独も NG。対象 ARN・Action を列挙する。
- **どうしても `*` が避けられないケース**（`ecr:GetAuthorizationToken` / `ecs:RegisterTaskDefinition` / `sts:GetSessionToken` 等、AWS が resource-level permissions を**サポートしない API**）は例外として受容するが、policy 内にインラインコメントで **(a) AWS 側の制約である旨、(b) blast radius、(c) 2.2.26-7 からの逸脱である** 旨を明記する（例：`terraform/project/modules/cicd/iam_codebuild.tf` の ECR/ECS statement）。
- **Deny 文 + `Resource = "*"` は対象外**。2.2.26-7 の「付与」= Allow を指すため、MFA 強制のような Deny セーフティネットは `Resource = "*"` で書いてよい（例：`shared/modules/iam/iam_group_mfa_enforced.tf`）。
- **Resource-based policy（KMS key policy / VPC Endpoint policy / S3 bucket policy）は 2.2.26 の対象外**で、サービス標準のパターンに従う：
  - **KMS key policy**：root に `kms:*` / `resources = ["*"]`（自キーを指す）を付けるのが公式推奨。これは違反ではない（`data "aws_iam_policy_document"` で記述、`project/modules/kms/kms.tf:50-65`）。
  - **VPC Endpoint policy**：`Allow *, *, *` + 他アカウント `Deny`（`shared/network/vpc_endpoints.tf:11-36`）が標準。
  - **S3 bucket policy**：SSL 強制などは `jsonencode` で Deny ポリシー。
- ポリシー DSL：小規模は `jsonencode`、複雑（dynamic statement など）は `data "aws_iam_policy_document"`（KMS で採用）。

## 8. KMS のパターン

- **KMS キーの定義は environments から渡す**（§6 の UI 原則に従う）。モジュール内の `locals` にキー一覧をハードコードせず、`variable "keys"` で受け取り、`for_each = var.keys` で展開。environments の locals に `kms_keys = { ... }` を書くことで「この環境にどんな目的のキーがあるか」が UI 側から一望できる。
- **shared / project の棲み分けは state 境界**：shared state 内のリソース（shared VPC flow log 用の logs key 等）は shared モジュールで管理、project state 内のリソース（Aurora / S3 / Secrets / project VPC flow log）は project モジュールで管理。同名（例：`logs`）のキーが両方にあっても用途は別物（それぞれ別の log destination を暗号化している）。state を跨いだ key 共有は原則しない。
- 必ず `enable_key_rotation = true`（デフォルトで年 1 回自動ローテーション）、`deletion_window_in_days = 30`。
- サービス別 `service` フィールドで CloudWatch Logs 等の Service Principal 許可を条件分岐（`dynamic "statement" { for_each = each.value.service != null ? ... : {} }`）。
- Alias は `alias/${name_prefix}-${each.key}`。

## 9. Provider / Backend / Version

- `required_version = ">= 1.10.0"`、`aws = "~> 6.0"`。
- Backend は S3 + **`use_lockfile = true`** + `encrypt = true`（DynamoDB ロックは使わない、S3 native lock）。
- `profile = "terraform"` を provider / backend 両方で指定。
- リージョンは **`ap-northeast-1` 固定**（`security_prohibitions.md` 2.1-2）。
- CloudFront / ACM(CF 用) 等で `us-east-1` が必要なモジュールは `versions.tf` で `configuration_aliases = [aws.us_east_1]` を宣言し、呼び出し側で `providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }` を渡す。

## 10. セキュリティ要件（`docs/security_prohibitions.md` 由来、必ず守る）

- **S3**：KMS 暗号化 (`aws_s3_bucket_server_side_encryption_configuration` + `sse_algorithm = "aws:kms"`) / Public Access Block / SSL 強制 Deny ポリシー (`aws:SecureTransport = "false"`) / `aws_s3_bucket_logging` / versioning。`force_destroy` は **TF コードでは設定しない**（prod で誤った destroy 時のデータ損失を避けるため）。destroy 時の BucketNotEmpty は `deploy-lifecycle` skill §3 の `full-destroy.sh` 側の retry + tag-based empty ループで処理する。
  - **重要（再発防止）**：S3 バケットは 1 個のバケットにつき 1 個の bucket policy しか持てない。`aws_s3_bucket_policy` リソースを**同じバケットに対して複数モジュールから作ると、最後の apply が勝って他の statement（例：SSL 強制 Deny）が消える**。複数モジュールが同一バケットのポリシーを制御する場合は、呼び出し側で統合 policy 1 つにマージすること（例：`cdn/s3_bucket_policy.tf` は CloudFront OAC + SSL Deny の 2 statement を 1 つの `aws_s3_bucket_policy.this` に入れて書き出す）。`scripts/verify-deploy.sh` §6 の spot check が本問題の早期検出装置。
- **RDS / Aurora**：`storage_encrypted = true` + `kms_key_id`、`manage_master_user_password = true` + `master_user_secret_kms_key_id`、`iam_database_authentication_enabled = true`、`rds.force_ssl = 1` をクラスタパラメータグループで設定。
- **ALB**：HTTPS のみ、`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`、`access_logs` 有効。
- **CloudFront**：`minimum_protocol_version = "TLSv1.2_2021"`、`viewer_protocol_policy = "redirect-to-https"`、`web_acl_id` で WAF アタッチ、`logging_config`、OAC で S3 保護。AWS が `TLSv1.2_2021` より新しい policy 名を追加した場合、**最新版にアップデートする（最低半年に一度は AWS 公式ドキュメントを確認）**。ハードコード文字列は陳腐化する。`origin_ssl_protocols.items` (VPC origin 等) も同様。
- **VPC**：VPC フローログ必須（無効化禁止）、SG で 0.0.0.0/0 無制限許可 / 0-65535 全開放禁止、IGW ルート禁止（CloudFront VPC Origin 用の **ルーティングしない** IGW のみ例外、`network/vpc.tf:16-27`）。
- **VPC Endpoint 経由アクセス**：ECR / Logs / SSM / Secrets Manager / STS / Firehose 等は shared VPC の Interface Endpoint 経由（TGW 越し）+ PHZ 関連付け。
- **監査・アクセスログは勝手に「別バケット」にしない**：同じバケットを prefix で切り、IAM を prefix レベル（Resource `arn:aws:s3:::bucket/<prefix>/*`）で分離する方が運用が軽い。バケット自体を増やす判断は、ライフサイクル / 暗号化 / 保管期間が本質的に違う場合のみ。
- **CloudWatch Logs / Firehose**：Log Group は KMS 暗号化 + `retention_in_days` 指定。Firehose delivery stream は KMS 暗号化 + S3 宛先へ書き込む IAM を最小権限で付与（`app/audit_logs.tf`）。
- **IAM**：identity policy で Resource/Action の過剰許可禁止、アクセスキー作成禁止、`"*"` 禁止（§7 参照）。
- **ALB**：`idle_timeout` を環境変数として明示（default 60s 任せにしない）。長時間 API 等で必要なら環境側で伸ばす。
- **ECS タスク定義（`ecs/<service>/ecs-task-def.jsonnet`）**：
  - **`readonlyRootFilesystem: true`** を可能な限り有効化。書き込み先（`/tmp` / `/var/cache/nginx` / `/var/run` など）は Fargate 対応の named `volumes` + `mountPoints` で個別マウント。Python アプリは `PYTHONDONTWRITEBYTECODE=1` を env に足して `.pyc` 生成を抑止。FireLens init コンテナは `/fluent-bit/etc` へ設定を書き戻すため除外（コメントで理由明記）。
  - **`stopTimeout: 30`** を明示。SIGTERM → SIGKILL までの graceful shutdown 予算。DB コネクション等を閉じる余裕を持たせる。Fargate 上限は 120 秒。
  - **コンテナ `healthCheck` と ALB target group の HC は意図的にずらす**：ECS `interval: 15` / ALB `interval: 30` で、ECS はタスク異常を早期検出、ALB は一時的揺らぎを平均化。task-def にコメントで役割分担を明記。

## 11. コーディング前チェック

- [ ] 置く場所：environment か module か（`main.tf` は environment のみ）
- [ ] ファイル名がリソース種別を表している／IAM・Log 等の補助リソースは別ファイル
- [ ] 補助リソースのファイル名：モジュール内で 1 つだけなら AWS サービス名のみ（`cloudwatch.tf` / `iam.tf`）、複数あるときのみ purpose 付き（`iam_codebuild.tf`）
- [ ] 物理名に AWS サービス名・短縮形 (rt/sg/igw 等)・`-shared-` を入れていない
- [ ] 論理名：同タイプが 1 種類 = `"this"` / 複数 = 役割名
- [ ] タグは `Name` のみ（default_tags と重複させない）
- [ ] `count` でなく `for_each`
- [ ] 新規 SG / rule は SG 専用ファイル（`security_group.tf` 単数 or `security_groups.tf` + `security_group_rules.tf` の 2 分割）にしか置いていない、他リソースと同居していない
- [ ] **variable に `default` を書いていない**（定数はハードコード、再利用は locals、環境依存は呼び出し側で明示）
- [ ] レーン / サービス依存なら `for_each`
- [ ] 関連する設定は 1 つの構造にまとめている（分離管理で運用ミスを招かない）
- [ ] 文字列操作を避け resource attribute / data source で参照している（`aws_elb_service_account` 等、AWS が data source で提供しているものをハードコードしていない）
- [ ] `data` の `for_each` は対応する `resource` の `for_each` と同じ集合を使っている
- [ ] `locals` に置いているのは 2 箇所以上で使う値だけ（1 回きりのものは展開している）
- [ ] environments 側で「この環境の挙動」が読めるようになっている（DB config / retention / feature flag 等を環境側に持ってきた）
- [ ] IAM identity policy の Resource を列挙（Allow + `"*"` 単独を避ける）／resource-based policy は §7 参照
- [ ] S3/Aurora/ALB/CloudFront のセキュリティ要件（§10）
- [ ] リージョン `ap-northeast-1`、CF 系のみ `us-east-1` エイリアス

## 12. 既存実装リファレンス

| やりたいこと | 参照先 |
|---|---|
| environment 全体 | `terraform/project/environments/dev/{main,locals,providers,versions}.tf` |
| 空 SG 殻 + for_each | `terraform/project/modules/network/security_groups.tf` |
| SG ルール消費側配置 | `terraform/project/modules/{app,lb,db,cdn}/security_group_rules.tf` |
| for_each サービス展開 | `terraform/project/modules/app/iam.tf` |
| KMS 多目的キー | `terraform/project/modules/kms/kms.tf` |
| S3 セキュリティ一式 | `terraform/project/modules/storage/s3.tf` |
| Aurora セキュリティ一式 | `terraform/project/modules/db/aurora.tf` |
| CloudFront + WAF + VPC Origin | `terraform/project/modules/cdn/cloudfront.tf` |
| VPC Endpoint policy | `terraform/shared/modules/network/vpc_endpoints.tf` |
| 再利用可能 IAM Policy | `terraform/project/modules/{db/iam_auth,storage/iam}.tf` |
| configuration_aliases | `terraform/project/modules/cdn/versions.tf` |
| 複数ファイル分割例 | `terraform/project/modules/network/*.tf` |
| ログバケット + ELB account ID map | `terraform/project/modules/logging/bucket_policy.tf` |
| S3 → EventBridge → CodePipeline | `terraform/project/modules/cicd/eventbridge.tf` |
| 監査ログ S3（暗号化 + SSL 強制 + lifecycle） | `terraform/project/modules/app/audit_logs.tf` |
| Firehose delivery stream | `terraform/project/modules/app/firehose_audit_logs.tf` |
| Firehose IAM (補助リソース分離) | `terraform/project/modules/app/iam_firehose.tf` |
| VPC Flow Log 3 分割パターン | `terraform/{shared,project}/modules/network/{vpc_flow_logs,cloudwatch_flow_log,iam_flow_log}.tf` |
