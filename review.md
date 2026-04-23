> shared/modules/kms
- localsでkeysの定義をしているのは少しわかりづらいかもしれない
  - moduleの引数でも良いかも

> shared/modules/network
- retention_in_daysは環境ごとに値を変える可能性があるので、moduleの引数にしよう、暗黙的なのは嫌なのでdefault引数は使わない
- cloudwatch_flow_log.tfはサービス名じゃないのでcloudwatchだけで良いかも
- route53_phz.tf内でのdataについて、意図しないvpc endpointを対象にしないようにresourceで定義しているものでfor_eachした方が良い
- vpc_endpoints.tf内でaws_security_groupが定義されていてわかりづらい。前回の指摘が


---


## project

### app
pending、レビューしてない

### cdn
- ssl
>    origin_ssl_protocols {
>      items    = ["TLSv1.2"]
>      quantity = 1
>    }
これは最新？
- signing
signing周りはon/offが切り替えできると良い
- route53は無印がお客様用、サブドメインが
- wafはお客様用と管理用で管理用はIP制限を入れる可能性がある。wafファイルを2つに分けてフラグ管理するかmoduleを分けるかした方が多分良い

### cicd
pending、レビューしてない

### db
var.db_config (Dict[Object]ってパラメータでバージョン情報やスペックをenvironments側のファイルを見ればわかるようにしようか、UIとしてのenvironmentsファイルの充実が目的

### dns/dns_firewall
pending、レビューしてない

### kms
shared側のkmsがあるけどそれとは別？

### lb
ok

### logging
- elb_account_idsはdataで取れないの？
- 構成変更でauditログはs3内のprefixで分けて権限を分けることにした

### network
- XXXXX_flow_logはそういう名前のリソースがあるように見えるから
- subnetはalb/ecs/dbで最低限分けるので、変数もネストして渡す必要があるが、全体的なreadabilityを優先
  - 別件だがlocals.tfも文字列処理やり過ぎててreadablity低過ぎ
  - 繰り返し使わないものはmain.tfにベタがきの方がまし

### storage
- cdn同様にpdfなどの一時URLによる配信自体をやらないprojectもあるので、他に依存関係が残っていたら対応して欲しい 


---

#### procject/app
- audit_logsはバケットを分けずに共通のログバケットに出力してprefixで分ける
  - ECSのログはaudit_logs以外のログも全てfirehoseでcloudwatchを経由しないで良い
- firehose_audit_logs.tfはルールによるとfirehose.tfで良いはず、横展開できていない. check方法を見直した方が良い
  - iamもこの程度なら1ファイルで良い


#### project/dns, dns_firewall
- manage_registrar_nsのような常にtrueのもののflag管理は不要
- dns_firewallは今回は使わない理解でok?つまりmoduleを呼び出さない？

#### cicd
- module作ってはいるもののビルドはローカルでやってるよね？
- 動作目検証ならenvironmentsからの呼び出しはないと思ってok?
