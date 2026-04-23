---
name: iam-design
description: IAM 設計方針。人間ユーザー / グループ / スイッチロール / MFA 強制の構造を決めるとき、および `terraform/shared/modules/iam` を触るときに参照。ECS/CodeBuild などのサービスロールは利用側モジュール内で閉じて定義するが、その際の共通原則（Allow の scope、MFA 条件、AssumeRole ポリシー、ファイル分割）もここで扱う。Use when designing IAM users, groups, permission/switch-role patterns, or editing any IAM module / role / policy in this repo.
---

# IAM Design Conventions

このリポジトリで IAM リソースを設計・実装するときの方針。

## Scope

- **shared/modules/iam（人間アカウント管理）**：IAM ユーザー、グループ（MFA 強制 + 権限 switch）、パスワードポリシー。§2〜§4 で構成と 2 層設計を定義。
- **利用側モジュール（サービスロール）**：ECS タスクロール、CodeBuild ロール、Firehose ロールなど。shared/iam には入れず、使う側のモジュール内で定義。§5〜§6 で Allow の scope / AssumeRole ポリシー / MFA Condition などの共通原則を定義。

関連 skill：全般的な Terraform 規約（ファイル分割・命名・tag）は `terraform-conventions`。デプロイ手順は `deploy-lifecycle`。

## 1. モジュール配置

- IAM ユーザー・グループ・パスワードポリシーは **`terraform/shared/modules/iam`** にまとめる。環境横断の人間アカウント管理なので shared state。
- **切り出しの条件**：現状は単一 AWS アカウント前提で shared state 内。AWS Organizations で複数アカウント管理に移行する or アカウントまたぎの IAM を統合管理する必要が出た時点で、`terraform/iam/` を独立 state として切り出す。切り出す際もファイル構造（§2）は維持する。
- IAM ロール（サービスロール、タスクロールなど）は **利用側モジュール内**で定義する（例：`project/modules/app/iam.tf` の ECS タスクロール、`project/modules/cicd/iam_codebuild.tf` の CodeBuild ロール）。shared/iam モジュールには入れない。

## 2. ファイル構成

`terraform/shared/modules/iam/` 配下：

```
iam_users.tf              # aws_iam_user + group membership
iam_policies.tf           # アカウント共通の IAM 設定 (password policy など)
iam_group_<name>.tf       # グループ 1 つにつき 1 ファイル
variables.tf
outputs.tf
```

- **グループは 1 グループ 1 ファイル**。`iam_group_admin.tf` / `iam_group_developer.tf` / `iam_group_mfa_enforced.tf` のように用途で分ける。
- グループ用の IAM ロール・ポリシー・アタッチメントも **同じファイル**に書いてよい（役割単位で凝集）。`terraform-conventions` §1 の「3 種類以上のリソース混在で分割」より「グループ単位の凝集」を優先する。
- `iam_groups.tf` のような「全グループをまとめた map」ファイルは作らない（variable で渡すより、グループごとの意図を明示する方が安全）。

## 3. ユーザーの持ち方

### Variable 定義

`variable "users"` は「ユーザー名を key、値に所属グループ名のリスト」を持つ map：

```hcl
variable "users" {
  type = map(object({
    groups = list(string)
  }))
}

# environments 側の locals
users = {
  alice = { groups = ["mfa-enforced", "developer"] }
  bob   = { groups = ["mfa-enforced", "admin"] }
}
```

### 実装ルール

- **ユーザーに直接ポリシーをアタッチしない**。権限は必ずグループ経由。
- **全ユーザーを必ず `mfa-enforced` グループに所属させる**。`iam_users.tf` の `aws_iam_user_group_membership` で `concat([aws_iam_group.mfa_enforced.name], each.value.groups)` により、users.groups で `mfa-enforced` を明示しなくても自動的に含まれるように実装する（§4 の MFA 強制を強制力ある形にするため）。
- それ以外のグループ（`developer` / `admin` など）は users.groups に明示して所属させる。

## 4. グループ設計（2 層構造）

グループは用途で 2 種類に分ける。

### A. 共通設定グループ（全ユーザーが所属）

- MFA 強制、パスワード自己変更許可、デフォルト Deny など、**全アカウント共通の制約**を付けるグループ。
- 例：`mfa-enforced`
  - ポリシー：MFA 未使用時の全 API Deny（`aws:MultiFactorAuthPresent = false` の Deny statement）。
- 全ユーザーを必ずこのグループに所属させる。

### B. 権限付与グループ（役割別）

- 開発者 / 管理者 / 読み取り専用 / セキュリティ担当など、**職務ごと**のグループ。
- **このグループ自体には業務権限を持たせない**。持たせるのは「対応する IAM ロールへの `sts:AssumeRole` 権限」だけ。
- 例：`developer` グループ → `developer-role` への AssumeRole のみ付与。
- グループ用 IAM ロールは同じファイル（`iam_group_developer.tf`）内で定義してよい：

  ```hcl
  resource "aws_iam_group" "developer" { ... }
  resource "aws_iam_role"  "developer" {
    assume_role_policy = <MFA 必須かつこのグループのユーザーのみ AssumeRole 可能>
  }
  resource "aws_iam_group_policy" "developer_assume" {
    # このグループには developer ロールへの AssumeRole だけ許可
  }
  # developer ロールに付ける業務権限
  resource "aws_iam_role_policy_attachment" "developer_*" { ... }
  ```

### なぜスイッチロールにするか

- 日常操作は最小権限グループ（AssumeRole のみ）で行い、危険な操作が必要なときだけ明示的にロール切替する。
- CloudTrail 上で「誰が、いつ、何の権限にスイッチしたか」が明確に残る。
- 権限見直しの際、業務ポリシーはロール側に集約されているので差分管理が楽。

## 5. ロール側の書き方

`assume_role_policy` の Condition は **2 軸を AND で併用** する：

### 2 軸の意味

- **MFA 条件** (`aws:MultiFactorAuthPresent = true`) = **認証強度の保証**
  - 目的：IAM User 認証情報が盗まれた場合に、AssumeRole で危険な権限を得られないようにする。
  - これだけでは「誰が AssumeRole するか」を絞れない。
- **グループ条件** (`aws:userId` に group name を含む) = **認可スコープの限定**
  - 目的：例えば `admin` グループに属さないユーザーが誤って admin ロールを AssumeRole しないようにする。
  - これだけでは MFA なしのセッションでも通ってしまう。

両方を AND で指定することで「MFA で認証強度を担保、かつ対応グループのユーザーだけが引き受けられる」ロールになる。片方だけでは不完全。

### 実装ルール

- ロール名は用途が分かる形（`<project>-<env>-developer` / `<project>-<env>-readonly`）。AWS サービス名は入れない（`terraform-conventions` §2）。
- タグベース制御（`aws:PrincipalTag/team`）を使う場合も、上記 2 軸（MFA + グループ）は必ず併用する。

### 権限グループロールの assume_role_policy サンプル

```hcl
data "aws_iam_policy_document" "developer_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    # MFA 必須
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    # developer グループ所属ユーザーのみ
    condition {
      test     = "StringLike"
      variable = "aws:userId"
      values   = ["*:${aws_iam_group.developer.name}"]
    }
  }
}
```

実ユーザーでの制御は `aws:userId` や Principal に `arn:aws:iam::<account>:group/<group>` を使う方法がある。複数ユーザーが同じロールに切り替える想定なら `aws:PrincipalTag` + AWS Identity Center を検討。

## 6. 権限記述の原則

### Allow / Deny で書き分ける

`security_prohibitions.md` 2.2.26-7 は **Allow 文のみが対象**（「付与」= Allow）。

- **Allow 文**：`Resource` または `Action` に `"*"` 単独は禁止（厳格解釈）。必ず ARN / Action を列挙する。
- **Deny 文**：`"*"` は許容。MFA 強制のような「明示的な拒否」は対象全体にかかる必要があるため。

### AWS API 側の制約による Allow 例外

AWS がリソースレベル権限をサポートしない API（`ecr:GetAuthorizationToken` / `ecs:RegisterTaskDefinition` / `ecs:DescribeTaskDefinition` / `sts:GetSessionToken` / `iam:ListVirtualMFADevices` など）は、scope 手段が存在しないため Allow + `Resource = "*"` を **例外として受容** する。ただし policy 内にインラインコメントで以下を明記：

- (a) AWS 側の制約である旨
- (b) blast radius（影響範囲）
- (c) 2.2.26-7 からの逸脱である旨

scope 可能な API なら絶対に列挙する（例外として安易に使わない）。

### Resource-Based Policy は別ルール

KMS key policy / VPC Endpoint policy / S3 bucket policy は 2.2.26 の対象外。サービス標準のパターンに従う → `terraform-conventions` §7 を参照。

### Terraform での書き方

- AWS マネージドポリシーは `aws_iam_role_policy_attachment` + `arn:aws:iam::aws:policy/...`
- ロール専用の小さなカスタムポリシーは `aws_iam_role_policy` インライン（`jsonencode`）
- 複数ロールで再利用するものは `aws_iam_policy` + `aws_iam_role_policy_attachment`

### アクセスキー禁止

IAM User 用アクセスキーは作らない（`security_prohibitions.md` 2.2.26-4）。CLI 利用が必要な場合は IAM Identity Center（SSO）+ AssumeRole で短命トークンを使う。

## 7. 設計前チェック

**配置の判断**
- [ ] 人間ユーザー / グループ / スイッチロール用 → `shared/modules/iam`
- [ ] サービスロール（ECS/CodeBuild/Firehose など）→ 利用側モジュール内
- [ ] グループ 1 つにつき 1 ファイル（`iam_group_<name>.tf`）

**ユーザー**
- [ ] ユーザーに直接ポリシーを付けていない（グループ経由）
- [ ] 全ユーザーが `mfa-enforced` グループに自動所属（`iam_users.tf` の concat パターン）
- [ ] アクセスキーを作っていない（`security_prohibitions.md` 2.2.26-4）

**グループ / ロール**
- [ ] 権限付与グループは対応ロールへの `sts:AssumeRole` 権限のみ（業務権限は持たせない）
- [ ] ロールの `assume_role_policy` に MFA 必須 + グループ所属の Condition が入っている

**ポリシー記述**
- [ ] identity policy の Allow 文で `Resource = "*"` 単独 / `Action = "*"` 単独を使っていない（§6）
- [ ] 避けられない場合（AWS が resource scope 非対応の API）はコード内コメントで逸脱理由を明記
- [ ] Deny 文での `Resource = "*"` は許容（§6）
- [ ] resource-based policy（KMS key / VPCE / S3 bucket）は `terraform-conventions` §7 参照

## 8. 参考

- 全般的な terraform 規約：`.claude/skills/terraform-conventions/SKILL.md`
- 禁止事項の原本：`docs/security_prohibitions.md` 2.2.26（IAM）
- 既存 IAM モジュール：`terraform/shared/modules/iam/`
- サービスロールの実装例：`terraform/project/modules/app/iam.tf`、`terraform/project/modules/cicd/iam_*.tf`
