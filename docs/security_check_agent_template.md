# セキュリティ検証サブエージェント テンプレート

## Claude Code 用

### 呼び出し方

```
Agent(subagent_type="Explore", prompt="<下記テンプレートを埋めたもの>")
```

### プロンプトテンプレート

```markdown
このリポジトリの Terraform コードを調査し、セキュリティ禁止事項への準拠状況を検証してください。

## 禁止事項
{{禁止事項の内容を簡潔に記載}}

## 確認ポイント
{{番号付きで確認すべき具体的な設定項目を列挙}}

## 調査範囲
{{対象ディレクトリ・ファイルパターンを指定}}

## 出力フォーマット（厳守）

### 判定サマリ
| リソース名 | ファイル:行 | 判定 | 理由(1行) |
|---|---|---|---|

### 非準拠の修正案
（非準拠がある場合のみ、具体的なTerraformコード片を提示）

### 備考
（補足事項があれば1-2行で）

簡潔に報告してください。詳細な説明は不要です。
```

---

## Cursor 用 (.cursorrules / プロンプトファイル)

### 使い方

1. 以下のプロンプトテンプレートをコピー
2. Cursor の Chat (Cmd+L) または Composer (Cmd+I) に貼り付け
3. `{{}}` を検証内容で置換して実行

### プロンプトテンプレート

```markdown
@workspace のTerraformコードを調査し、以下のセキュリティ禁止事項への準拠を検証して。

## 禁止事項
{{禁止事項の内容を簡潔に記載}}

## 確認ポイント
{{番号付きで確認すべき具体的な設定項目を列挙}}

## 調査範囲
{{対象ディレクトリ・ファイルパターンを指定}}

## 回答フォーマット

### 判定サマリ
| リソース名 | ファイル:行 | 判定 | 理由(1行) |
|---|---|---|---|

### 非準拠の修正案
非準拠がある場合のみ、修正後のTerraformコードを提示して。

### 備考
補足があれば1-2行で。

簡潔に回答して。
```

### Cursor Agent モード用（自動修正あり）

```markdown
@workspace のTerraformコードで以下のセキュリティ禁止事項に違反している箇所を見つけて自動修正して。

## 禁止事項
{{禁止事項の内容}}

## 確認ポイント
{{確認項目}}

## 調査範囲
{{ファイルパターン}}

## ルール
- 非準拠のリソースを見つけたらそのまま修正して
- 修正前後の差分を表示して
- 判定サマリテーブルも出力して
```

---

## 全検証一括実行（Claude Code）

```python
# 全12検証を並列実行する場合のイメージ
checks = [
    {"id": 1,  "title": "CloudFront+WAF紐付け",          "scope": "modules/cdn/, modules/storage/"},
    {"id": 2,  "title": "S3暗号化・SSL強制・アクセスログ",  "scope": "modules/storage/, modules/logging/"},
    {"id": 3,  "title": "SGルール無制限トラフィック",        "scope": "modules/**/security_group*.tf"},
    {"id": 4,  "title": "VPCフローログ有効化",              "scope": "modules/network/"},
    {"id": 5,  "title": "VPCエンドポイントDenyポリシー",    "scope": "modules/network/"},
    {"id": 6,  "title": "Aurora暗号化・パブリックアクセス",   "scope": "modules/db/"},
    {"id": 7,  "title": "IAMポリシー権限範囲",              "scope": "modules/app/, modules/cicd/"},
    {"id": 8,  "title": "ECR VPCエンドポイント経由",        "scope": "modules/network/, modules/app/"},
    {"id": 9,  "title": "KMS暗号化網羅性",                  "scope": "modules/ 全体"},
    {"id": 10, "title": "SecretsManagerシークレット管理",    "scope": "modules/db/, modules/app/, ecs/"},
    {"id": 11, "title": "DNS Firewall設定",                 "scope": "modules/dns_firewall/"},
    {"id": 12, "title": "CloudFormationサービスロール",      "scope": "terraform/, ecs/"},
]
```
