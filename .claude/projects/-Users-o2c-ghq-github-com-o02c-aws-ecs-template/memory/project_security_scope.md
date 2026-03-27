---
name: security-scope-boundary
description: VPC Flow Logs, CloudTrail, AWS Config, Security Hub, IAM Access Analyzer, SNS通知(セキュリティイベント) are managed by the Organizations management account
type: project
---

以下は Organizations 管理アカウント側で設定・管理される：
- VPC Flow Logs
- CloudTrail
- AWS Config
- Security Hub
- IAM Access Analyzer
- SNS通知（セキュリティイベント: GuardDuty, Config, Access Analyzer等）

**Why:** マルチアカウント構成で、これらのセキュリティ基盤はStackSets等で全アカウントに一括適用されるため、個別アカウントのTerraformでは管理しない。

**How to apply:** このプロジェクトのTerraformでこれらのリソースを追加提案しないこと。セキュリティ差分分析時にも「管理アカウント側で対応済み」として扱う。
