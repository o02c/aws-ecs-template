# 構成内容

## 前提構成
- AWSで複数サービスを同時構築するための雛形となるリポジトリ
- ユーザー同線と管理者動線があり、いずれもcloudFront→alb→s3, ecsで公開する、アカウント,VPC,DBは共用
    * S3からの静的資材の公開を想定している
- S3からの一時URLによるPDFのダウンロード機能を利用する場合がある(サービスによる)
- ecs serviceのデプロイはecspressoで行う

## ディレクトリ構成

terraform/
  environment/
    /dev
      main.tf
      <オプションになる構成要素1>.tf
      <オプションになる構成要素2>.tf
      variables.tf
      environment.auto.tfvars
      secret.auto.tfvars.example
      secret.auto.tfvars # gitignore
modules/
    network/
      vpc, subnet, route_table, 必要な場合はinternet/nat gateway
      全てのsecurity_groupの作成(inbound/outboundは各モジュール側の責任で設定)
    cdn/
      cloudfrontおよび周辺
      !複数同線の可能性あり!
o   lb/
      alb(cloudfrontのvpc origin前提のためinteranl)
      !複数同線の可能性あり!
    app/
      ecs cluster, ecr, IAM, ログ関連
      !サービス以下の設定はecspressoで行う!
      !複数同線の可能性あり!
    db/
      rds aurora for postgresql(iam認証), および周辺
      !複数同線の可能性あり!
    cicd/
      デプロイ用の色々
    <名前未定>
      S3からの静的資材の公開用の資材、IAMを作成してecspressoで参照して貰えば良さそう

## ルール
- default_tagでProjectName, Environment, ManagedByを定義する(名前は一般的なものであれば変更か）
- リソース名は<Projectoname>-<Environment>-<リソース識別し>とする、ただしリソース識別子はAWSサービス名は**含めない**, xxx-prod-ec2のような名前は情報が増えていないので避ける
- main.tfはenvironments配下のみで利用可能、modulesでは具体的なawsサービス名やterrformのリソース名や内容に関連する名称でecs_cluster.tfのように定義する
- セクションコメントは以下のような形式とする
```
# --------------------------------------------------------------------------------
# Auto Start Stop
# --------------------------------------------------------------------------------
```
- コメントは#始まりで統一
- outputとvariableは必要になって初めて追加する、表示用は不要
- countは原則利用しない、for_eachでstateファイルの可読性を担保する

