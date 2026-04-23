---
name: deploy-lifecycle
description: Terraform ベースの deploy / 疎通確認 / destroy の標準手順。手動で terraform apply や docker build を並べるのではなく、justfile と scripts/ に用意されたレシピ・シェルスクリプトを使う。CDK 版ワークフローは §8 を参照。Use when the user asks to deploy, set up, verify, tear down, destroy, or reset the infrastructure.
---

# Deploy / Verify / Destroy Lifecycle

`terraform apply` や `ecspresso deploy` を個別に叩かず、**用途に合ったスクリプトを必ず使う**。スクリプト側には順序依存・S3 versioned object の空化・ログ削除などの再現困難なノウハウが入っている。

## Scope

- 扱う：Terraform 版のライフサイクル（`full-deploy.sh` / `full-destroy.sh` / justfile レシピ）、ECS サービス更新、疎通確認、orphan 掃除。
- 扱わない：Terraform のコード規約（→ `terraform-conventions`）、IAM 設計（→ `iam-design`）、CDK 版のスタック設計（§8 の参考レシピのみ）。

## 0. 事前 setup

初回のみ：

- `aws configure --profile terraform` で AWS 認証情報を `[profile terraform]` に設定（`~/.aws/config` / `~/.aws/credentials`）。
- `~/.env` に `DOMAIN_NAME=o2c.click`（変更したいなら書き換え）。`AWS_PROFILE=terraform` も推奨。
- `just generate-signing-keypair`（任意：CloudFront 署名 URL を使う場合）で keypair 生成 → `terraform/project/environments/dev/secret.auto.tfvars` に自動反映。
- `brew install just ecspresso awscli docker`、Docker Desktop 起動。
- `terraform/shared/environments/dev/environment.auto.tfvars` と `terraform/project/environments/dev/environment.auto.tfvars` を確認（project_name / environment / domain_name）。

## 1. 用途別のエントリポイント

| 目的 | 実行 | 中身 | 完了判定 |
|---|---|---|---|
| ゼロから全部立てて疎通確認まで | `just setup` | `bash scripts/full-deploy.sh` | 最後に `=== Deploy Complete ===` が出力、health check が OK |
| 全部消す（S3 versioned 含む） | `just destroy` | 確認プロンプト → `bash scripts/full-destroy.sh` | 最後に `=== Destroy Complete ===`。state list が空 |
| shared TF だけ立てる | `just shared-apply-auto` | `terraform apply -auto-approve` | `Apply complete!` |
| shared TF だけ消す | `just shared-destroy` | `terraform destroy -auto-approve -refresh=false` + orphan log group 削除 | `Destroy complete!` |
| project TF だけ立てる | `just project-apply-auto` | `terraform apply -auto-approve` | `Apply complete!` |
| project TF だけ消す | `just project-destroy` | `terraform destroy -auto-approve` + orphan log group 削除 | `Destroy complete!` |
| 疎通確認のみ | `just check` | `curl https://{lane}.${DOMAIN_NAME}/health` | 両 lane で `OK` |
| 拡充疎通確認（TLS / 全ログ destination） | `just verify-deploy` | `bash scripts/verify-deploy.sh` | 最後に `=== Verify PASSED ===` |
| 個別ビルド & デプロイ | `just ship <service>` | ECR login → docker build/push → ecspresso deploy | ecspresso の stable 検知 |
| 全サービスをビルド → デプロイ | `just ship-all` | 上記の全サービス版 | 同上 |

**失敗時**：`Error:` を含む出力が出て exit code 非 0。`/tmp/*.log` にリダイレクトしているならそこで `grep Error` するか、`TF_LOG=info` を付けて原因を特定する。途中で中断した場合は state と AWS が食い違うことがあるので §5-4 の「partial state 復旧」を参照。

確認用レシピ：

- `just shared-plan` / `just project-plan` — plan のみ
- `just diff <service>` — 動作中サービスとの差分
- `just verify <service>` / `just verify-all` — ecspresso verify

## 2. full-deploy.sh が順番にやること

`scripts/full-deploy.sh`（= `just setup`）は 6 ステップを **`set -euo pipefail` で順に実行**。途中で失敗したら exit 1 で中断し、後続ステップは動かない。

1. **shared TF**：`terraform init -upgrade` → `apply -auto-approve`。VPC・TGW・KMS・IAM を作成。
2. **project TF**：同様に init → apply。ECS cluster・ECR・ALB・CloudFront・S3 などを作成。
3. **SSM Parameter Store**：Django secret key を `openssl rand -hex 32` で生成し、placeholder のときだけ上書き。
4. **Docker build & push**：`ecs/nginx` と `apps/{user-api, admin-api}` を `linux/amd64` でビルドし ECR へ push。aws-for-fluent-bit:init-latest を private ECR にミラー。
5. **ECS deploy**：各サービスで `ecspresso deploy`（`IMAGE_TAG` と `NGINX_IMAGE_TAG` を渡す）。
6. **Health check**：30 秒待機後、`https://{user,admin}.${DOMAIN_NAME}/health` に `curl -sf --max-time 10`。1 つでも失敗したら exit 1。

### 順序の理由

- **1 → 2** は state 依存。project は shared の state output を `terraform_remote_state` で参照するため逆順だと失敗する。
- **2 → 3** は SSM Parameter Store resource が project TF 側で作られるため（placeholder 値で作成 → step 3 で実値に更新）。
- **3 → 4 → 5** は ECS task definition が SSM parameter と ECR image を参照するため、両方揃ってから deploy。
- **5 → 6** は ECS service が稼働してから health check を打つため。30 秒待機は ALB target group が healthy になる待ち時間。

### 各ステップの失敗時の挙動

- **1-2 (TF apply)**：`Error: ...` で中断。`/tmp/` のログで原因特定（lock issue / AWS auth / resource conflict など）。state に部分的な変更が書かれていることがあるので、`terraform state list` で確認してから再実行。
- **3 (SSM)**：AWS 認証エラーなら中断。既作成のインフラはそのまま残る。認証修正後 `just setup` で再実行すれば、TF apply は no-op、SSM から再開される。
- **4 (Docker build)**：Docker daemon 未起動 / ECR 認証失敗 / ビルドエラーで中断。再実行は冪等。
- **5 (ECS deploy)**：ecspresso の rollback 機構でサービスは以前の task definition に戻る。infra は残る。
- **6 (Health check)**：HTTP 200 以外なら exit 1、Deploy Complete は出ない。DNS 伝播遅延の可能性もあるので 1-2 分待ってから `just verify-deploy` で詳細確認。

## 3. full-destroy.sh の設計背景と 7 ステップ

### なぜ単純な `terraform destroy` では足りないか

AWS ECS / CloudFront / ALB / Firehose は destroy 直後も数秒〜数分ログをバケットに書き込み続ける。並行して Terraform が S3 bucket を削除しようとすると `BucketNotEmpty` で失敗する。また versioning 有効バケットはデリートマーカーが残るので `aws s3 rm --recursive` だけでは掃除できない。さらに VPC Endpoint の PHZ を同時破棄すると `dns_entry[0]` の refresh が失敗する。ECR の pull-through cache repo は AWS が自動生成するので TF タグが付かず、tag-based 掃除から漏れる。

`full-destroy.sh` はこれら **「TF destroy 単独では詰むトラップ」を順序制御とリトライで吸収** する設計。だから 7 ステップに分かれている。

### 7 ステップ

`scripts/full-destroy.sh`（= `just destroy`、確認プロンプトあり）：

1. **ECS サービス削除**：`ecspresso delete --force --terminate`、`DRAINING` が抜けるまで最大 60 回 5s 待機。
2. **S3 バケット空化 1 回目**：`resourcegroupstaggingapi` で `ManagedBy=terraform` のバケットを列挙し、`aws s3 rm --recursive` + `python3 scripts/empty-versioned-bucket.py` で空化（タグベースなので命名変更に強い）。
3. **ECR プルスルーキャッシュ削除**：`ecr-public/*` で自動生成されるキャッシュリポジトリを `--force` で削除（AWS 自動生成のため TF タグなし → prefix match）。
4. **project TF destroy**：`init -upgrade` → `tf_destroy_with_retry`。**`BucketNotEmpty` 失敗時は tag-based で再空化して最大 4 回リトライ**（`TF_DESTROY_MAX_ATTEMPTS` で上書き可）。これにより `force_destroy = true` を TF コードに入れずに済み、prod での誤爆リスクを排除。
5. **S3 バケット空化 2 回目**：shared destroy 前の belt-and-suspenders。
6. **shared TF destroy**：`tf_destroy_with_retry` + `-refresh=false`。`-refresh=false` は VPC endpoint + PHZ 同時破棄時に `dns_entry[0]` が空になり refresh が失敗するのを回避するため（削除してはいけない）。
7. **CloudWatch ロググループ削除**：Terraform 管理下ではなく apply 後に AWS が自動生成する log group をパターンマッチで削除（`/aws/vpc/flow-log/*`、`/ecs/<project>-<env>/*`、us-east-1 の `aws-waf-logs-<project>-<env>-*`）。

タグベース探索を採用しているので、リソース名の prefix 変更や `-shared-` 等の接頭辞変更があっても `full-destroy.sh` を書き換える必要はない。ハードコードが残っているのは：

- ECS クラスタ名 / サービス名（ecspresso 側のライフサイクル管理）
- ECR pull-through cache の prefix（AWS 自動生成）
- orphan log group のネーム pattern（AWS 自動生成、TF タグなし）

`destroy -refresh=false` と 2 段階 S3 空化、ログ削除ステップは **手動 destroy で必ず踏むトラップ**。直接 `terraform destroy` を叩かないこと。

## 4. 前提

- `AWS_PROFILE=terraform`（既定）。`~/.aws/config` に `[profile terraform]` が設定済みであること。
- `AWS_REGION=ap-northeast-1` 固定。
- Docker daemon が動いていること（`full-deploy.sh` のビルド工程用）。
- `ecspresso` がインストール済み（`which ecspresso` で確認）。
- `just` コマンド利用可能。
- `.env` の `DOMAIN_NAME`（既定 `o2c.click`）。変更したいなら `.env` で上書き。
- Signing keypair は `just generate-signing-keypair` で事前生成し、`secret.auto.tfvars` にセット。

## 5. よくあるシナリオ

### 5-1. TF のリファクタリングを検証したい

```
just shared-plan              # 差分だけ見る
just shared-apply-auto        # 適用
# 確認系（aws ec2 describe-vpcs 等）
just shared-destroy           # 片付け
```

project まで影響する場合は同様に `project-*`。両方を通しで検証したい場合は `just setup` → `just destroy`。

### 5-2. アプリだけ入れ替えたい

インフラが既に立っているなら：

```
just ship user-api            # build → push → ecspresso deploy
just check                    # health check
```

### 5-3. 完全にリセットしたい

```
just destroy                  # プロンプトに `destroy` と入力
just setup                    # 再度立ち上げ
```

### 5-4. Partial state 復旧（apply が中断したとき）

ネット断や権限不足で `just setup` が中断すると、AWS に作成済みのリソースが state に書き戻されていない "orphan" として残ることがある。次の apply は `already exists` エラーで失敗する。

復旧手順：

1. `terraform -chdir=... state list | wc -l` で state 件数を確認。AWS 側の実数と食い違っていないか。
2. `Error: already exists` が出たリソースを AWS CLI で手動削除（ALB / RDS / Firehose / TGW attachment / IAM policy など）。
3. `bash scripts/full-destroy.sh` で state 分を destroy（retry が orphan と state の両方に対応）。
4. 全 state が 0 件になったら `just setup` を最初からやり直す。

**重要**：state と AWS の不整合を「無視して再 apply」は絶対にしない。必ず一度 destroy して綺麗にしてから fresh setup する。

## 6. やってはいけないこと

- 手動で `terraform destroy` を叩く → S3 / ECS / ECR の片付け順序を飛ばすので失敗する。必ず `just destroy` または `bash scripts/full-destroy.sh` を経由。
- `scripts/destroy.sh` / `scripts/setup.sh` / `scripts/deploy.sh` を使う → これらは **古い構成（`terraform/environments/dev` 単一ディレクトリ前提）** で、現在のディレクトリ構成では動かない。新スクリプト（`full-deploy.sh` / `full-destroy.sh` と justfile レシピ）を使うこと。
- `just shared-apply-auto` を project 先に打つ → state 参照で失敗。順番は必ず shared → project。
- 手で S3 バケットを空にしてから `terraform destroy` → versioned object やデリートマーカーで引っかかる。`empty-versioned-bucket.py` を使う（full-destroy.sh が呼ぶ）。また各バケット resource に `force_destroy = true` を付けて TF 側でも空化できるようにしておく（現状の dev 用モジュールは全部設定済み）。

## 8. Gotchas

- **`yes destroy | just destroy` は動かない**。`_confirm-destroy` recipe のインタラクティブ `read -p` がパイプ入力を受け取らず Abort する。自動実行では `bash scripts/full-destroy.sh` を直接呼ぶこと。
- **`/aws/vpc/flow-log/<prefix>` の orphan log group**：`just shared-destroy` を単独実行した後、CloudWatch Logs が即座には削除されず次の apply で `ResourceAlreadyExistsException` を起こすケースがある。justfile の `shared-destroy` / `project-destroy` recipe に orphan 削除を入れて再発防止済み。手動 apply 直前で `aws logs delete-log-group --log-group-name /aws/vpc/flow-log/<prefix>` を叩くと確実。
- **access-logs バケットへの log 追記は destroy 中も続く**：CloudFront / ALB / Firehose は destroy 完了直前までログを書き込みし得るので、一度の `empty_tagged_buckets` + `terraform destroy` では `BucketNotEmpty` で失敗する場合がある。対応として `full-destroy.sh` の `tf_destroy_with_retry` が **destroy 失敗時に tag-based で再度空化 → 最大 4 回リトライ** する。この仕組みがあるので `aws_s3_bucket.force_destroy` は TF 側で設定しない（prod での誤爆防止）。
- **SES recipient verify + SNS email subscription は apply 後に Gmail で手動 confirm が必要**：
  - `aws_ses_email_identity` / `aws_sns_topic_subscription` は verify/confirm 要求だけ投げるリソース。apply 自体は "success" 表示で完了する。
  - AWS が送る confirmation メール（SES 1 通 + SNS topic 数だけ = `critical` と `warning` の 2 通、計 3 通）が Gmail に届くので、リンクを手動クリックして `Verified` / `Confirmed` 状態に遷移させる必要あり。
  - 未 confirm のまま `/api/test/send-email` を叩くと SES SendEmail が 400 で弾き、未 confirm の SNS subscription は CloudWatch Alarm が発火しても silent drop。
  - `verify-deploy.sh` に `aws ses get-identity-verification-attributes` / `aws sns list-subscriptions-by-topic --query 'Subscriptions[].SubscriptionArn'` の確認ステップを入れている。PendingConfirmation のままなら WARN で知らせる。

## 9. 参考

- スクリプト本体：`scripts/full-deploy.sh`、`scripts/full-destroy.sh`、`scripts/empty-versioned-bucket.py`
- レシピ一覧：`justfile`（`just --list` で閲覧）
- CDK 版を使う場合：`just cdk-deploy-all` / `just cdk-destroy-all`（本ドキュメントは Terraform 版の扱い）
