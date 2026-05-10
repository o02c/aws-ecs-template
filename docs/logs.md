# ログ一覧

## 集約方針

container 出力 (gunicorn / Django / nginx stdout) は CloudWatch Logs を経由せず、**FireLens (Fluent Bit) → Kinesis Firehose → S3** で 1 本化する。`type=audit` を持つレコードだけ別 Firehose stream に振り分け、同じバケットの異なる prefix に落とす。CloudWatch Logs はインフラ層 (VPC flow log, FireLens 自身) のみ。

## S3

すべてのアクセスログ / 集約ログは **共通の access-log バケット 1 個**に prefix 分割で集める。WAF だけは AWS 仕様で `aws-waf-logs-` 接頭辞のバケットが必要なので別。

### `{project}-{env}-access-logs-{account_id}` (ap-northeast-1)

`terraform/project/modules/logging/s3.tf`

ライフサイクル: 90 日 → GLACIER, 365 日 → 削除（dev デフォルト、env で変えられる）。暗号化: AES256（AWS 仕様で SSE-S3 必須）。

| Prefix | 中身 | 出力元 |
|---|---|---|
| `alb/{lane}/` | ALB アクセスログ (lane ごと) | ALB → S3 直接 (`terraform/project/modules/lb/alb.tf`) |
| `cloudfront/` | CloudFront 標準ログ (単一 distribution) | CloudFront → S3 直接 (`terraform/project/modules/cdn/cloudfront.tf`) |
| `s3/{lane}/` | アセットバケットの S3 access log | S3 logging (`terraform/project/modules/storage/s3.tf`) |
| `audit/year=YYYY/month=MM/day=DD/` | 監査イベント (`type=audit`) | Firehose `{project}-{env}-audit` (`terraform/project/modules/app/firehose.tf`) |
| `audit-errors/year=YYYY/.../{error-type}/` | 監査 Firehose の配信失敗 | 同上 (Firehose error_output) |
| `ecs-logs/year=YYYY/month=MM/day=DD/` | container stdout (非 audit、nginx + Django) | Firehose `{project}-{env}-ecs-logs` (同上) |
| `ecs-logs-errors/year=YYYY/...` | ecs-logs Firehose の配信失敗 | 同上 |
| `fluent-bit/extra.conf` | FireLens 追加設定の格納先 (オブジェクト 1 個) | terraform `fluent_bit_config.tf` が apply 時に upload |
| `artifact/` | CodePipeline artifact bucket access log (CI/CD module 有効時のみ) | `terraform/project/modules/cicd/s3.tf` |

### `aws-waf-logs-{project}-{env}-{account_id}` (us-east-1)

`terraform/project/modules/logging/s3_waf.tf`

WAF v2 が直接配信する専用バケット (CloudFront WAF は us-east-1 必須)。`aws-waf-logs-` 接頭辞は AWS 必須命名。

| Prefix | 中身 |
|---|---|
| `AWSLogs/{account_id}/WAFLogs/cloudfront/{project}-{env}/...` | WAF ログ (単一 WACL) |

`terraform/project/modules/cdn/waf.tf`, `waf_logging.tf`

### shared 側

| バケット | 中身 |
|---|---|
| `{project}-{env}-access-logs` (account_id 無し) | shared 側 ALB アクセスログ等 (`terraform/shared/modules/network/`) |

## CloudWatch Logs

container 出力の集約には使わない。AWS マネージド機能 (VPC flow / FireLens 自身) が出すログのみ。

| Log group | 用途 | 保持 |
|---|---|---|
| `/ecs/{project}-{env}/fluent-bit` | FireLens (Fluent Bit) の起動 / エラー診断 | `var.fluent_bit_log_retention_days` (dev 7 日) |
| `/aws/vpc/flow-log/{project}-{env}` | project VPC のフローログ | `var.flow_log_retention_days` (30 日) |
| `/aws/vpc/flow-log/shared-{env}` | shared VPC のフローログ | 同上 |

すべて KMS 暗号化済み (CW Logs 用 KMS key)。

> **container app log は CW Logs にない**。Django / gunicorn / nginx の stdout は FireLens → Firehose → S3 `ecs-logs/` 配下に落ちる。CW で追いたいケースは `fluent-bit` 自体の起動失敗デバッグくらい。

## Kinesis Data Firehose

`terraform/project/modules/app/firehose.tf` で 2 stream 作る。両者とも buffer 5MB / 60 秒 (env で変更可)、GZIP、KMS 暗号化。

| Stream | 入口 | 出口 |
|---|---|---|
| `{project}-{env}-audit` | FireLens が `type=audit` のレコードを振り分け | access-log bucket `audit/year=YYYY/...` |
| `{project}-{env}-ecs-logs` | FireLens がそれ以外を全部振り分け | access-log bucket `ecs-logs/year=YYYY/...` |

## アプリ側の責任

`docs/path-routing-app-guide.md#26-ログ出力-本番のパイプライン前提` を参照。要点:

- container stdout は **1 行 1 JSON object**
- 監査ログは `logging.getLogger("audit").info(..., extra={"type": "audit", ...})` で出す
- traceback は `JsonFormatter` が `"traceback"` フィールドにまとめて 1 行化済み

## 関連

- [docs/path-routing-app-guide.md](path-routing-app-guide.md) — アプリチームから見たログ要件
- [docs/architecture.md](architecture.md) — インフラ全体図
