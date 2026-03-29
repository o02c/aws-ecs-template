# ecspresso 運用ガイド

## 概要

ecspressoはECSサービス/タスク定義のデプロイツール。Terraformとはライフサイクルを分離し、ECSリソースの管理を担当する。

- Terraform: インフラ (VPC, ALB, ECR, IAM, CloudWatch Logs等)
- ecspresso: ECSサービス/タスク定義のデプロイ、ロールバック、スケーリング

## ディレクトリ構成

```
ecs/
  <service-name>/
    ecspresso.yml            # ecspresso設定
    ecs-service-def.jsonnet  # サービス定義
    ecs-task-def.jsonnet     # タスク定義
```

## tfstate連携

### S3バックエンドからの読み込み

```yaml
# ecspresso.yml
plugins:
  - name: tfstate
    config:
      url: s3://<bucket>/<key>
```

AWS認証はSDK標準の認証チェーン (`AWS_PROFILE`, `AWS_REGION` 等) を使用。

### テンプレート記法

Jsonnetファイル内で `{{ tfstate }}` テンプレートを使用する。

```jsonnet
{
  image: "{{ tfstate `module.app.aws_ecr_repository.this['user-api'].repository_url` }}:latest",
}
```

### 配列形式リソース名のクォート

`for_each` で作成されたリソースの参照にはシングルクォートを使用する。
ダブルクォートだとJSON/Jsonnetのエスケープと競合するため。

```jsonnet
# OK - シングルクォート
"{{ tfstate `module.lb['user'].aws_lb_target_group.this.arn` }}"

# NG - ダブルクォートだとJSON変換時にエスケープが壊れる
"{{ tfstate `module.lb[\"user\"].aws_lb_target_group.this.arn` }}"
```

参考: ecspresso (tfstate-lookup) はダブルクォートとシングルクォートを同様に扱う。

### 処理順序

1. Jsonnetとしてファイルを読み込み、JSONへレンダリング
2. `{{ tfstate }}` 等のテンプレート処理を実行

そのため `.jsonnet` ファイルはJsonnetとして文法的に正しい必要がある。

## 基本操作

```bash
# 設定の検証
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso verify

# テンプレートのレンダリング確認
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso render task-definition
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso render service-definition

# デプロイ
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso deploy

# ロールバック (前リビジョンのタスク定義に戻す)
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso rollback

# スケーリング
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso scale --tasks 2

# 差分確認
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso diff

# ECS Exec (コンテナ内でコマンド実行)
AWS_PROFILE=terraform AWS_REGION=ap-northeast-1 ecspresso exec --command /bin/sh
```

## Terraform側の責務

ecspressoが参照するリソースはTerraformで事前に作成する:

- ECSクラスタ
- ECRリポジトリ (イメージのビルド・pushはCI/CDの責務)
- ALBターゲットグループ
- セキュリティグループ
- サブネット
- IAMロール (タスク実行ロール、タスクロール)
- CloudWatch Logsロググループ

## Terraform outputsの活用

ecspressoからtfstate内のリソースを参照するため、environments配下の `outputs.tf` にecspresso用のoutputsを定義できる。
mapのネストされた値にはドット記法でアクセスできないため、フラットなoutputを使うか、リソースアドレスを直接指定する。

## 参考

- [ecspresso handbook v2対応版](https://zenn.dev/fujiwara/books/ecspresso-handbook-v2)
- [fujiwara/tfstate-lookup](https://github.com/fujiwara/tfstate-lookup)
- [kayac/ecspresso](https://github.com/kayac/ecspresso)
